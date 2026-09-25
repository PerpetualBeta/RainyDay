import AppKit
import CoreGraphics
import ServiceManagement
import Sparkle

extension Notification.Name {
    /// Posted whenever `activationSuspended` changes, from either the status
    /// menu or the Settings toggle, so the status icon stays honest about
    /// which one is true regardless of which one changed it.
    static let activationSuspendedChanged = Notification.Name("RainyDayActivationSuspendedChanged")
}

/// App lifecycle + idle-driven screensaver window controller. Also
/// owns the status item, settings window, and hotkey infrastructure.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private var idleTimer: Timer?
    private var windows: [ScreensaverWindow] = []
    private var wallpaperWindows: [WallpaperWindow] = []
    private var screenChangeObserver: NSObjectProtocol?
    /// Signature of the display layout the currently-live windows were
    /// built for. `nil` when no windows exist. See `handleScreenChange`.
    private var builtForLayout: String?
    private var defaultsObserver: NSObjectProtocol?
    /// Earliest moment the idle-tick is allowed to dismiss after an
    /// activation. Activating via hotkey (or status-menu click) is
    /// itself recent user input, so the immediate next idle reading
    /// would be ~0 seconds and we'd auto-dismiss the saver we just
    /// opened. Suppress the dismiss until past this timestamp.
    private var dismissAllowedAfter: Date = .distantPast
    /// Earliest moment the idle-tick is allowed to ACTIVATE. Pushed
    /// forward when the system wakes from sleep or the screen unlocks
    /// — without this, a Mac that's been asleep would trigger our
    /// saver the instant you log back in (system idle accumulates
    /// during sleep, and would already be well past our threshold).
    private var activationAllowedAfter: Date = .distantPast
    private var wakeObservers: [NSObjectProtocol] = []
    /// True while the saver windows are up but paused because something
    /// covers them: the lock screen or a sleeping display. See
    /// `pauseForCover(reason:)`. Also stops a display-layout change from
    /// rebuilding them, which would start the rain again. See
    /// `handleScreenChange`. Cleared in `tearDownWindows`.
    private var pausedForCover = false
    /// True from `screensDidSleep` until the next wake or unlock, which
    /// clears it in `observeWakeAndUnlock`. The idle tick will not start the
    /// saver into a dark display.
    private var displayAsleep = false
    /// True between `com.apple.screensaver.didstart` and its `didstop`:
    /// macOS's own screen saver, not ours. Tracked from the notifications
    /// because there is no query for it. The idle tick will not start the
    /// saver on top of it.
    private var nativeScreensaverRunning = false

    private var statusItem: StatusItem?
    private var statusItemVisibilityObserver: NSObjectProtocol?
    private var hotkeyManager = JorvikHotkeyManager(signature: JorvikHotkeyManager.rainyDaySignature)
    private var settingsWindow: SettingsWindow?

    // Sparkle update controller. Owns the SPUStandardUpdaterController
    // — created lazily so initial-launch performance isn't affected.
    let userDriverDelegate = RainyDayUserDriverDelegate()
    lazy var sparkleUpdater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: userDriverDelegate
    )

    // MARK: - Defaults keys + accessors

    /// Default idle threshold, in minutes. Override via Settings or
    ///   `defaults write cc.jorviksoftware.RainyDay idleMinutes 10`
    private let defaultIdleMinutes: Int = 5
    private let activateHotkeyKey   = "activateHotkey"
    private let screenshotHotkeyKey = "screenshotHotkey"

    private var idleThresholdSeconds: Double {
        let m = UserDefaults.standard.integer(forKey: "idleMinutes")
        return Double(m > 0 ? m : defaultIdleMinutes) * 60
    }
    private var lockOnDismiss: Bool {
        UserDefaults.standard.bool(forKey: "lockOnDismiss")
    }
    /// User-requested "don't activate on idle right now", distinct from
    /// every reason the app holds activation back by itself (a lock, a
    /// call): this one is someone explicitly asking. Activate Now still
    /// works; only the idle tick checks it.
    private var activationSuspended: Bool {
        UserDefaults.standard.bool(forKey: "activationSuspended")
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        rdLog("applicationDidFinishLaunching — idle threshold \(Int(idleThresholdSeconds))s"
              + (UserDefaults.standard.bool(forKey: "activationSuspended") ? ", activation SUSPENDED from a previous session" : ""))
        // Seed the registration domain so `integer(forKey:)` returns the
        // intended default when the user hasn't explicitly written the
        // key. `@AppStorage` only writes to UserDefaults on user change —
        // its declared default is purely what the UI displays. Without
        // this registration, an unset `cycleMinutes` reads as 0, gets
        // clamped to 1 in `makeConfigScript`, and the saver rotates
        // backgrounds every minute instead of every five.
        UserDefaults.standard.register(defaults: [
            "cycleMinutes": 5,
            "idleMinutes":  15,
        ])
        BackgroundsStore.ensureSeeded()
        registerAtLoginIfNeeded()
        // Touch the lazy property so the updater starts and begins
        // its scheduled-check timer.
        _ = sparkleUpdater
        createStatusItem()
        // Create or remove the menu-bar item when the user toggles its
        // visibility in Settings. The rain overlay is wholly independent
        // of the status item, so this only affects menu access.
        statusItemVisibilityObserver = NotificationCenter.default.addObserver(
            forName: JorvikStatusItemVisibility.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyStatusItemVisibility()
        }
        registerStoredHotkeys()
        startIdlePolling()
        applyWallpaperState()
        // React to the user toggling the wallpaper setting in Settings.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyWallpaperState()
        }
        // Re-evaluate windows when displays connect/disconnect/reconfigure
        // (new monitor plugged in mid-screensaver, etc.).
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.handleScreenChange()
        }
        observeWakeAndUnlock()
    }

    /// Relaunching from /Applications is the user's only way back to a
    /// hidden menu-bar icon, so restore visibility here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        JorvikStatusItemVisibility.handleReopen()
        return true
    }

    /// After waking from sleep or unlocking the screen, suppress saver
    /// activation for a grace period (30s). System idle time keeps
    /// counting during sleep/lock, so without this the user would
    /// fight the saver immediately on every wake/unlock.
    /// Named once rather than spelled at each use — it is matched against a
    /// notification name as well as observed, and two spellings of the same
    /// string is how that kind of check silently stops matching.
    static let screenIsUnlockedNotification = "com.apple.screenIsUnlocked"

    /// Whether waking should LOCK the screen rather than merely dismiss the saver.
    ///
    /// Pulled out as a pure function because it decides a security behaviour, and
    /// a security behaviour should be checkable without a machine to put to sleep.
    /// All four conditions have to hold:
    ///
    /// - **It is a wake, not an unlock.** An unlock means the user has just
    ///   authenticated; locking them straight back out would be absurd.
    /// - **The user asked for lock-on-dismiss.** Otherwise this is not our business.
    /// - **The saver is actually up.** Waking a Mac that was not running the saver
    ///   must not lock it — that would be an app seizing a machine it was not
    ///   covering.
    /// - **The screen is not already locked.** Usually it is: with the screen-lock
    ///   delay set to immediate, macOS locks the session about a second after the
    ///   display sleeps. Locking again would be a harmless no-op, but asking first
    ///   keeps the log honest about which of the two actually did it.
    static func shouldLockOnWake(notification: String,
                                 lockOnDismiss: Bool,
                                 saverIsUp: Bool,
                                 screenAlreadyLocked: Bool) -> Bool {
        notification != screenIsUnlockedNotification
            && lockOnDismiss
            && saverIsUp
            && !screenAlreadyLocked
    }

    private func observeWakeAndUnlock() {
        let ws = NSWorkspace.shared.notificationCenter
        let dn = DistributedNotificationCenter.default()

        // Named in the log, because three different notifications share this
        // closure and one message for three causes is what turned a four-second
        // race into a fortnight of log-reading.
        let onWake: (Notification) -> Void = { [weak self] note in
            guard let self = self else { return }
            // Every one of the three notifications this closure handles means
            // the display is awake again.
            self.displayAsleep = false
            self.activationAllowedAfter = Date().addingTimeInterval(30)
            rdLog("wake/unlock event (\(note.name.rawValue)) — activation suppressed for 30s")

            // The three notifications do NOT mean the same thing, and treating
            // them as one left lock-on-dismiss depending on a setting this app
            // does not own.
            //
            // An **unlock** means the user has just authenticated. Locking again
            // would be absurd, so dismiss and leave it.
            //
            // A **wake** means the machine came back with the saver still up. If
            // lock-on-dismiss is on, the screen must not be handed back unlocked.
            // macOS usually has it covered already — with the screen-lock delay
            // set to immediate, loginwindow locks the session about a second
            // after the display sleeps, measured. But that delay is a System
            // Settings value: set it to five minutes and the same code leaves a
            // five-minute hole with the feature switched on. So check rather
            // than assume, and lock only when it is genuinely needed.
            let mustLock = Self.shouldLockOnWake(
                notification: note.name.rawValue,
                lockOnDismiss: self.lockOnDismiss,
                saverIsUp: !self.windows.isEmpty,
                screenAlreadyLocked: LockScreen.screenIsLocked)
            if mustLock {
                rdLog("woke with the saver up and the screen UNLOCKED — locking, not just dismissing")
            }
            self.dismissWindows(triggerLock: mustLock)
        }

        wakeObservers.append(ws.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
            using: onWake))
        wakeObservers.append(ws.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main,
            using: onWake))
        wakeObservers.append(dn.addObserver(
            forName: Notification.Name(Self.screenIsUnlockedNotification),
            object: nil, queue: .main, using: onWake))

        // The handshake in `observeLockThenPause` hears only a lock the saver
        // asked for itself. Lock Now, a hot corner or control-command-Q while
        // the saver was up went unheard, and the rain kept drawing behind the
        // lock screen. Display sleep had no handler at all. Both pause, and
        // the saver stays up: `onWake` locks only when `saverIsUp`, so windows
        // torn down here would hand a lock-on-dismiss user an unlocked desktop
        // whenever the macOS lock delay is not immediate.
        wakeObservers.append(dn.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.pauseForCover(reason: "com.apple.screenIsLocked")
        })
        wakeObservers.append(ws.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.displayAsleep = true
            self?.pauseForCover(reason: "screensDidSleep")
        })
        wakeObservers.append(dn.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstart"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.nativeScreensaverRunning = true
            rdLog("com.apple.screensaver.didstart — macOS's own screen saver started")
        })
        wakeObservers.append(dn.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstop"), object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self, self.nativeScreensaverRunning else { return }
            self.nativeScreensaverRunning = false
            // Idle time kept climbing the whole time it was up, so restart the
            // countdown rather than let the next tick activate the instant it
            // ends.
            self.activationAllowedAfter = Date().addingTimeInterval(self.idleThresholdSeconds)
            rdLog("com.apple.screensaver.didstop — macOS's own screen saver ended; idle countdown restarted")
        })
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleTimer?.invalidate()
        if let obs = screenChangeObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = defaultsObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = statusItemVisibilityObserver { NotificationCenter.default.removeObserver(obs) }
        let ws = NSWorkspace.shared.notificationCenter
        let dn = DistributedNotificationCenter.default()
        for obs in wakeObservers {
            ws.removeObserver(obs)
            dn.removeObserver(obs)
        }
        wakeObservers.removeAll()
        cleanupLockObserver()
        tearDownWallpaperWindows()
        dismissWindows(triggerLock: false)
        rdLog("applicationWillTerminate")
    }

    // MARK: - Login auto-launch

    /// Auto-register for launch-at-login on the very first run only.
    /// Running the installer (or first-launching the .app) is the
    /// consent gesture; the README documents the auto-launch behaviour.
    /// Every subsequent launch leaves the system state alone — if the
    /// user disables Rainy Day in System Settings → Login Items, we
    /// don't fight them back. The Settings → General → "Launch at
    /// Login" toggle is the only thing that toggles the state after
    /// first run.
    private func registerAtLoginIfNeeded() {
        let firstRunKey = "didAttemptInitialLoginRegistration"
        let alreadyAttempted = UserDefaults.standard.bool(forKey: firstRunKey)
        let service = SMAppService.mainApp
        guard !alreadyAttempted else {
            rdLog("login item: status=\(service.status.rawValue), respecting user choice")
            return
        }
        UserDefaults.standard.set(true, forKey: firstRunKey)
        guard service.status == .notRegistered || service.status == .notFound else {
            rdLog("login item: first run, status already \(service.status.rawValue) — no action")
            return
        }
        do {
            try service.register()
            rdLog("login item: first-run registration done")
        } catch {
            rdLog("login item: first-run registration failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Hotkeys

    private func registerStoredHotkeys() {
        hotkeyManager.register(HotkeyStore.read(activateHotkeyKey), slot: .activate) { [weak self] in
            self?.activateNowFromHotkey()
        }
        hotkeyManager.register(HotkeyStore.read(screenshotHotkeyKey), slot: .screenshot) { [weak self] in
            self?.captureScreenshot()
        }
    }

    private func activateHotkeyChanged(_ cfg: HotkeyConfig) {
        hotkeyManager.register(cfg, slot: .activate) { [weak self] in
            self?.activateNowFromHotkey()
        }
    }
    private func screenshotHotkeyChanged(_ cfg: HotkeyConfig) {
        hotkeyManager.register(cfg, slot: .screenshot) { [weak self] in
            self?.captureScreenshot()
        }
    }

    // MARK: - Idle polling

    private func startIdlePolling() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// Set while activation is being held back by a locked screen, so the
    /// reason is logged once per lock rather than on every tick.
    private var activationHeldByLock = false
    /// Mirror `activationHeldByLock`, for the other reasons activation is
    /// held back. Each logs its reason once, not every second.
    private var activationHeldByNativeScreensaver = false
    private var activationHeldByDisplaySleep = false
    private var activationHeldByAssertion = false
    /// Latch for the held-off log line in the dismiss branch — the tick runs
    /// every second and a pointer can travel for several of them.
    private var dismissHeldUnarmed = false

    private func tick() {
        let idle = systemIdleSeconds()
        if windows.isEmpty {
            // Checked first and unconditionally: this is not the app noticing
            // something about the world, it is someone having asked not to be
            // interrupted. No log line: the toggle logs the transition.
            guard !activationSuspended else { return }
            if idle >= idleThresholdSeconds && Date() >= activationAllowedAfter {
                // Never start behind a lock screen. loginwindow sits above the
                // saver level, so nothing would be visible: the app would spin
                // a WebGL render loop for an audience of nobody until someone
                // came back to the machine.
                //
                // There was no guard here at all, and this log proves the path
                // is taken: an idle-driven activation began 15 minutes into a
                // locked span on 2026-07-07 — 15 minutes being the threshold.
                //
                // Rainy Day only wastes power doing this. The same gap in ASCII
                // Saver turns the camera on behind the lock screen, which is
                // where it was found.
                if LockScreen.screenIsLocked {
                    if !activationHeldByLock {
                        rdLog("idle threshold reached but the screen is locked — not activating")
                        activationHeldByLock = true
                    }
                    return
                }
                activationHeldByLock = false

                // Nor on top of macOS's own screen saver, which sits at the
                // same window level, so there is no telling which is on top.
                if nativeScreensaverRunning {
                    if !activationHeldByNativeScreensaver {
                        rdLog("idle threshold reached but macOS's own screen saver is running — not activating")
                        activationHeldByNativeScreensaver = true
                    }
                    return
                }
                activationHeldByNativeScreensaver = false

                // Nor into a display that has gone dark. On a laptop on
                // battery this is often the timer that fires first.
                if displayAsleep {
                    if !activationHeldByDisplaySleep {
                        rdLog("idle threshold reached but the display is asleep — not activating")
                        activationHeldByDisplaySleep = true
                    }
                    return
                }
                activationHeldByDisplaySleep = false

                // Something else is asking macOS to keep the display on: a
                // video call, a film, a presentation. Idle time says nobody has
                // touched the keyboard, and that is exactly what watching
                // something looks like. See `DisplayWake`.
                if DisplayWake.somethingIsHoldingTheDisplayAwake {
                    if !activationHeldByAssertion {
                        rdLog("idle threshold reached but something is holding the display awake — not activating")
                        activationHeldByAssertion = true
                    }
                    // Restart the countdown rather than merely skipping this
                    // tick. Idle has been climbing all through the call, so
                    // without this the saver would appear the instant the call
                    // ended, which is the moment it is least wanted.
                    activationAllowedAfter = Date().addingTimeInterval(idleThresholdSeconds)
                    return
                }
                if activationHeldByAssertion {
                    rdLog("display assertion released — idle countdown restarted")
                    activationHeldByAssertion = false
                }

                rdLog("idle=\(Int(idle))s ≥ threshold — activating")
                showWindows()
            }
        } else if idle < 1.0 && Date() >= dismissAllowedAfter {
            // The windows' own event monitor ignores movement until the pointer
            // has come to rest, because movement that follows through from the
            // gesture which STARTED the saver is not a request to end it. This
            // path has to give the same answer. It polls system idle time, so
            // it sees that something happened without seeing what.
            guard windows.allSatisfy(\.dismissArmed) else {
                if !dismissHeldUnarmed {
                    rdLog("system idle dropped but the pointer is still moving — holding off")
                    dismissHeldUnarmed = true
                }
                return
            }
            dismissHeldUnarmed = false
            rdLog("system idle dropped — dismissing")
            dismissWindows(triggerLock: lockOnDismiss)
        }
    }

    private func systemIdleSeconds() -> Double {
        let anyEvent = CGEventType(rawValue: ~UInt32(0)) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    // MARK: - Window management

    private func showWindows() {
        // Suppress idle-driven auto-dismiss for 2 seconds after
        // activation. Without this, hotkey/menu activations would be
        // killed by their own user input — the keypress that triggered
        // activation also resets system idle to 0, and the next
        // idle-tick would dismiss.
        dismissAllowedAfter = Date().addingTimeInterval(2.0)
        for screen in NSScreen.screens {
            let win = ScreensaverWindow(screen: screen) { [weak self] in
                self?.dismissWindows(triggerLock: self?.lockOnDismiss ?? false)
            }
            windows.append(win)
            win.activate()
        }
        builtForLayout = Self.screenLayoutSignature()
        rdLog("showed \(windows.count) screensaver window(s) for layout \(builtForLayout ?? "?")")
    }

    /// True between the first `dismissWindows(triggerLock:true)` call
    /// and the eventual teardown. Guards against re-entry — even
    /// though each ScreensaverWindow removes its eventMonitor on
    /// first fire, the mouse can cross a display boundary and
    /// trigger two windows' monitors almost simultaneously. Without
    /// this flag we'd call LockScreen.lock() twice and arm two
    /// observe-lock-then-pause cycles.
    private var lockDismissInProgress = false

    private func dismissWindows(triggerLock: Bool) {
        guard !windows.isEmpty else { return }
        if triggerLock {
            guard !lockDismissInProgress else {
                rdLog("dismiss with lock — already in progress, ignoring re-entry")
                return
            }
            lockDismissInProgress = true
            // Tearing down on the same frame as the lock-screen
            // animation completes reliably flashes a frame or two of
            // desktop between the saver disappearing and loginwindow's
            // UI fully covering the display. Earlier attempts to time
            // the teardown off `com.apple.screenIsLocked` couldn't
            // close that gap deterministically — the notification can
            // lead the visual lock by a frame, and any added delay is
            // guesswork.
            //
            // Instead: don't tear down on lock at all. Lock the screen,
            // pause the WebGL render loop when the lock confirms (the
            // page exposes `window.rainyDayPause()`), and let the
            // existing wake/unlock observer in observeWakeAndUnlock()
            // tear down on `screenIsUnlocked`. The lock screen is at a
            // higher window level than `.screenSaver`, so it provably
            // covers our windows the moment it's up — there's no path
            // by which the desktop becomes visible to the user.
            rdLog("dismiss with lock — pausing on screenIsLocked, teardown deferred to unlock")
            // Pause now, not when the lock confirms. The lock screen normally
            // covers us in 0.1 to 0.4s, but under load it has taken over 4s,
            // and all that time the rain carried on as if the key press had not
            // been heard. A still frame answers the input at once.
            pauseForCover(reason: "dismissed, waiting for the lock screen")
            observeLockThenPause()
            LockScreen.lock()
        } else {
            tearDownWindows()
        }
    }

    private var lockObserver: NSObjectProtocol?
    private func observeLockThenPause() {
        // Nothing to wait for if the screen is already locked. macOS locks the
        // session itself when the display sleeps, so a saver that has been up
        // past the display-sleep timeout is dismissed onto an already-locked
        // session: `SACLockScreenImmediate` succeeds at doing nothing, and no
        // transition means no `com.apple.screenIsLocked` will ever arrive.
        // Waiting four seconds for it and then declaring failure is what the
        // log did for four months. Pause and carry on instead — the outcome is
        // the same as a lock that confirmed, because the screen is locked.
        if LockScreen.screenIsLocked {
            pauseForCover(reason: "screen already locked before the request, no handshake needed")
            return
        }
        let center = DistributedNotificationCenter.default()
        // Idempotent — clear any stale observer from a previous cycle.
        if let prev = lockObserver { center.removeObserver(prev); lockObserver = nil }

        lockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // The pausing itself is done by the permanent lock observer in
            // `observeWakeAndUnlock`, which hears this same notification.
            // This one only confirms the lock for the safety net below.
            self.cleanupLockObserver()
            // The saver paused when it was dismissed, so the permanent
            // observer logs nothing now. This line keeps the lock's latency
            // readable in the log.
            rdLog("screenIsLocked received — the lock screen is up")
        }
        // Safety net: if no lock notification arrives within 4 seconds
        // (SACLockScreenImmediate failed, loginwindow hung, framework
        // symbol removed in a future macOS — whatever the cause) the
        // saver would otherwise stay up indefinitely with no lock UI
        // ever appearing over it. Fall back to a normal teardown so we
        // don't leave the user stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self = self, self.lockObserver != nil else { return }
            self.cleanupLockObserver()
            // Ask, do not assume. The old line here read "lock likely failed",
            // which the app had no way of knowing: all it had observed was a
            // notification that did not arrive. Those are different facts, and
            // conflating them sent three investigations down the wrong road.
            if LockScreen.screenIsLocked {
                self.pauseForCover(reason: "no screenIsLocked in 4s, but the screen IS locked")
            } else {
                rdLog("no screenIsLocked in 4s and the screen is NOT locked — tearing down")
                self.tearDownWindows()
            }
        }
    }

    /// Pause the saver windows, once, while something covers them. Several
    /// observers can hear the same event; the first one pauses and logs.
    /// There is no resume: a paused saver is only ever dismissed, by the wake
    /// or unlock path, which locks first if it must.
    private func pauseForCover(reason: String) {
        guard !windows.isEmpty, !pausedForCover else { return }
        pausedForCover = true
        for win in windows { win.pauseAnimation() }
        rdLog("\(reason) — pausing animation; the saver stays up until dismissed")
    }

    private func cleanupLockObserver() {
        if let obs = lockObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            lockObserver = nil
        }
    }

    private func tearDownWindows() {
        // A teardown ends the dismiss this handshake belonged to, so the
        // observer has nothing left to hear. Leaving it armed let a wake
        // arriving mid-handshake orphan it rather than cancel it.
        cleanupLockObserver()
        for win in windows { win.deactivate() }
        windows.removeAll()
        // Clear the re-entry guard so the next dismiss cycle can lock
        // again. Called from both the normal teardown paths
        // (non-lock dismiss, post-unlock unlock-observer) and the
        // safety-net timeout in observeLockThenPause.
        lockDismissInProgress = false
        pausedForCover = false
        dismissHeldUnarmed = false
        if wallpaperWindows.isEmpty { builtForLayout = nil }
        rdLog("dismissed screensaver windows")
    }

    /// Fingerprint of the physical display layout — the only thing a
    /// screensaver or wallpaper window is actually built from.
    ///
    /// Deliberately excludes `visibleFrame`. `visibleFrame` shrinks and
    /// grows as the menu bar and Dock come and go, and a fullscreen
    /// window at `.screenSaver` level covers the menu bar — so a
    /// signature including it would change as a *result* of showing our
    /// own window. See `handleScreenChange` for why that matters.
    ///
    /// Sorted by display ID so a reordering of `NSScreen.screens` with
    /// unchanged geometry reads as no change. Frames are rounded to
    /// whole points: display frames are integral in practice, and
    /// rounding removes floating-point jitter from the comparison.
    private static func screenLayoutSignature() -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.map { screen -> String in
            let id = (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
            let f = screen.frame
            return String(
                format: "%u:%d,%d,%dx%d@%.1f",
                id,
                Int(f.origin.x.rounded()), Int(f.origin.y.rounded()),
                Int(f.size.width.rounded()), Int(f.size.height.rounded()),
                screen.backingScaleFactor)
        }
        .sorted()
        .joined(separator: "|")
    }

    /// `NSApplication.didChangeScreenParametersNotification` does not
    /// mean "a display was connected or disconnected". It fires for any
    /// change to the screen configuration, and on macOS 27 showing a
    /// window at `.screenSaver` level is itself such a change — the
    /// notification arrives 1-3ms after `win.activate()`, every time.
    ///
    /// Rebuilding unconditionally therefore re-triggers the very
    /// notification being handled: teardown, rebuild, notification,
    /// teardown, rebuild. Measured at ~30 rebuilds/second, 13,119 in a
    /// single day. The user-visible symptom is not a flicker but a
    /// frozen scene: each rebuild reloads `index.html`, which paints
    /// the first background (`coast-beach.jpg`, alphabetically first)
    /// and starts a fresh `cycleMinutes` rotation timer. A page that
    /// lives 35ms never reaches a 5-minute timer, so the saver shows
    /// that one image forever.
    ///
    /// The fix is to rebuild only when the thing the windows depend on
    /// actually differs. Showing a window does not move a display, so
    /// the signature is unchanged and the loop stops at the first hop.
    private func handleScreenChange() {
        // Nothing on screen to rebuild — nothing to decide.
        guard !windows.isEmpty || !wallpaperWindows.isEmpty else { return }

        let current = Self.screenLayoutSignature()
        guard current != builtForLayout else {
            rdLog("screen parameters changed but display layout is unchanged (\(current)) — not rebuilding")
            return
        }
        rdLog("display layout changed: \(builtForLayout ?? "none") → \(current)")

        // Recreate any wallpaper windows so they match the new layout.
        if !wallpaperWindows.isEmpty {
            rdLog("screen layout changed — recreating wallpaper windows")
            tearDownWallpaperWindows()
            showWallpaperWindows()
        }
        // Same for active screensaver windows.
        // A rebuild reloads the page and starts the rain from scratch. While
        // paused the saver is covered and only waiting to be dismissed.
        if !windows.isEmpty, pausedForCover {
            rdLog("screen layout changed while the saver is paused — not recreating screensaver windows")
        } else if !windows.isEmpty {
            rdLog("screen layout changed — recreating screensaver windows")
            dismissWindows(triggerLock: false)
            showWindows()
        }
    }

    // MARK: - Animated wallpaper

    /// Read the `animatedWallpaper` UserDefaults flag and bring the
    /// wallpaper windows into the matching state. Called at launch
    /// and whenever UserDefaults posts didChange.
    private func applyWallpaperState() {
        let on = UserDefaults.standard.bool(forKey: "animatedWallpaper")
        if on && wallpaperWindows.isEmpty {
            showWallpaperWindows()
        } else if !on && !wallpaperWindows.isEmpty {
            tearDownWallpaperWindows()
        }
    }

    private func showWallpaperWindows() {
        for screen in NSScreen.screens {
            let win = WallpaperWindow(screen: screen)
            win.show()
            wallpaperWindows.append(win)
        }
        builtForLayout = Self.screenLayoutSignature()
        rdLog("animated wallpaper: showed \(wallpaperWindows.count) window(s)")
    }

    private func tearDownWallpaperWindows() {
        for w in wallpaperWindows { w.hide() }
        wallpaperWindows.removeAll()
        if windows.isEmpty { builtForLayout = nil }
        rdLog("animated wallpaper: hidden")
    }

    // MARK: - Status item visibility

    /// Build the menu-bar item, unless the user has hidden it. Safe to
    /// call again after a hide (the item is rebuilt fresh).
    private func createStatusItem() {
        guard JorvikStatusItemVisibility.isVisible else { return }
        statusItem = StatusItem(appDelegate: self)
    }

    /// Bring the menu-bar item into line with the persisted visibility
    /// flag. Creates it when shown, removes it when hidden. The rain
    /// overlay and wallpaper windows are untouched either way.
    func applyStatusItemVisibility() {
        if JorvikStatusItemVisibility.isVisible {
            if statusItem == nil { createStatusItem() }
        } else if let item = statusItem {
            item.remove()
            statusItem = nil
        }
    }

    // MARK: - Status menu actions

    /// For the status menu's label and icon to read without owning the key.
    func isActivationSuspended() -> Bool {
        activationSuspended
    }

    /// Flips `activationSuspended`. The Settings toggle writes the same key
    /// directly (via `@AppStorage`) rather than calling this, but both paths
    /// post `.activationSuspendedChanged` so the status icon stays correct
    /// whichever one changed it.
    func toggleActivationSuspended() {
        let suspended = !activationSuspended
        UserDefaults.standard.set(suspended, forKey: "activationSuspended")
        rdLog(suspended ? "activation suspended from status menu" : "activation resumed from status menu")
        NotificationCenter.default.post(name: .activationSuspendedChanged, object: nil)
    }

    func activateNowFromMenu() {
        guard windows.isEmpty else { return }
        rdLog("activate-now from status menu")
        showWindows()
    }

    private func activateNowFromHotkey() {
        guard windows.isEmpty else { return }
        rdLog("activate-now from hotkey")
        showWindows()
    }

    func openSettings() {
        if settingsWindow == nil {
            // Build the shortcut rows with their on-change callbacks
            // wired to update HotkeyManager registration in real time.
            // While the recorder is listening, the app's own hotkeys come down
            // so that pressing the shortcut already set records it instead of
            // starting the saver.
            let suspend: (Bool) -> Void = { [weak self] recording in
                self?.hotkeyManager.setRecordingSuspended(recording)
            }
            let activate = JorvikHotkeyRow(
                label: "Activate now",
                storageKey: activateHotkeyKey,
                onChange: { [weak self] cfg in self?.activateHotkeyChanged(cfg) },
                onRecordingChanged: suspend
            )
            let screenshot = JorvikHotkeyRow(
                label: "Screenshot",
                storageKey: screenshotHotkeyKey,
                onChange: { [weak self] cfg in self?.screenshotHotkeyChanged(cfg) },
                onRecordingChanged: suspend
            )
            settingsWindow = SettingsWindow(
                activateRecorder: activate,
                screenshotRecorder: screenshot
            )
        }
        settingsWindow?.show()
    }

    // MARK: - Screenshot

    private func captureScreenshot() {
        guard let target = currentScreensaverWindow() else {
            rdLog("screenshot: no active screensaver window — ignoring hotkey")
            return
        }
        // Pressing the screenshot hotkey is itself recent user input
        // (idle drops to 0). Without extending the dismiss window, the
        // next 1Hz idle-tick would catch the low-idle reading and
        // close the saver a second after the screenshot finishes.
        // 2 seconds matches the activation grace.
        dismissAllowedAfter = Date().addingTimeInterval(2.0)
        Screenshot.capture(from: target.webView)
    }

    private func currentScreensaverWindow() -> ScreensaverWindow? {
        let mouse = NSEvent.mouseLocation
        return windows.first(where: { NSPointInRect(mouse, $0.screen.frame) })
            ?? windows.first
    }
}
