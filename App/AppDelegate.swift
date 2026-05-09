import AppKit
import CoreGraphics
import ServiceManagement
import Sparkle

/// App lifecycle + idle-driven screensaver window controller. Also
/// owns the status item, settings window, and hotkey infrastructure.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private var idleTimer: Timer?
    private var windows: [ScreensaverWindow] = []
    private var wallpaperWindows: [WallpaperWindow] = []
    private var screenChangeObserver: NSObjectProtocol?
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

    private var statusItem: StatusItem?
    private var hotkeyManager = HotkeyManager()
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

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        rdLog("applicationDidFinishLaunching — idle threshold \(Int(idleThresholdSeconds))s")
        BackgroundsStore.ensureSeeded()
        registerAtLoginIfNeeded()
        // Touch the lazy property so the updater starts and begins
        // its scheduled-check timer.
        _ = sparkleUpdater
        statusItem = StatusItem(appDelegate: self)
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

    /// After waking from sleep or unlocking the screen, suppress saver
    /// activation for a grace period (30s). System idle time keeps
    /// counting during sleep/lock, so without this the user would
    /// fight the saver immediately on every wake/unlock.
    private func observeWakeAndUnlock() {
        let ws = NSWorkspace.shared.notificationCenter
        let dn = DistributedNotificationCenter.default()

        let onWake: (Notification) -> Void = { [weak self] _ in
            guard let self = self else { return }
            self.activationAllowedAfter = Date().addingTimeInterval(30)
            rdLog("wake/unlock event — activation suppressed for 30s")
            // Also dismiss any saver windows that may already be up
            // (e.g., system displayed lock above an active saver session).
            self.dismissWindows(triggerLock: false)
        }

        wakeObservers.append(ws.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
            using: onWake))
        wakeObservers.append(ws.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main,
            using: onWake))
        wakeObservers.append(dn.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil, queue: .main, using: onWake))
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleTimer?.invalidate()
        if let obs = screenChangeObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = defaultsObserver { NotificationCenter.default.removeObserver(obs) }
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

    private func registerAtLoginIfNeeded() {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            rdLog("login item: already enabled")
        case .requiresApproval:
            rdLog("login item: requires user approval (System Settings → Login Items)")
        case .notRegistered, .notFound:
            do {
                try service.register()
                rdLog("login item: registered for launch at login")
            } catch {
                rdLog("login item: register failed — \(error.localizedDescription)")
            }
        @unknown default:
            rdLog("login item: unknown status \(service.status.rawValue)")
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

    private func tick() {
        let idle = systemIdleSeconds()
        if windows.isEmpty {
            if idle >= idleThresholdSeconds && Date() >= activationAllowedAfter {
                rdLog("idle=\(Int(idle))s ≥ threshold — activating")
                showWindows()
            }
        } else if idle < 1.0 && Date() >= dismissAllowedAfter {
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
        rdLog("showed \(windows.count) screensaver window(s)")
    }

    private func dismissWindows(triggerLock: Bool) {
        guard !windows.isEmpty else { return }
        if triggerLock {
            // Don't tear down on a fixed timer — the macOS lock-screen
            // animation can take 1–2 seconds and any guess here either
            // flashes the desktop (too short) or feels laggy (too long).
            // Instead, observe the system's `com.apple.screenIsLocked`
            // distributed notification: tear down only AFTER macOS
            // confirms the lock screen is up and covering us. The saver
            // windows stay visible until then, so the visual transition
            // is screensaver → lock screen with no desktop in between.
            rdLog("dismiss with lock — waiting for screenIsLocked")
            observeLockThenTearDown()
            LockScreen.lock()
        } else {
            tearDownWindows()
        }
    }

    private var lockObserver: NSObjectProtocol?
    private func observeLockThenTearDown() {
        let center = DistributedNotificationCenter.default()
        // Idempotent — clear any stale observer from a previous cycle.
        if let prev = lockObserver { center.removeObserver(prev); lockObserver = nil }

        lockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            rdLog("screenIsLocked received — tearing down")
            self.cleanupLockObserver()
            self.tearDownWindows()
        }
        // Safety net: if no lock notification arrives within 4 seconds
        // (osascript permission denied, lock-screen subsystem hung),
        // tear down anyway so we don't leak the windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self = self, self.lockObserver != nil else { return }
            rdLog("screenIsLocked timeout — tearing down anyway")
            self.cleanupLockObserver()
            self.tearDownWindows()
        }
    }

    private func cleanupLockObserver() {
        if let obs = lockObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            lockObserver = nil
        }
    }

    private func tearDownWindows() {
        for win in windows { win.deactivate() }
        windows.removeAll()
        rdLog("dismissed screensaver windows")
    }

    private func handleScreenChange() {
        // Recreate any wallpaper windows so they match the new layout.
        if !wallpaperWindows.isEmpty {
            rdLog("screen layout changed — recreating wallpaper windows")
            tearDownWallpaperWindows()
            showWallpaperWindows()
        }
        // Same for active screensaver windows.
        if !windows.isEmpty {
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
        rdLog("animated wallpaper: showed \(wallpaperWindows.count) window(s)")
    }

    private func tearDownWallpaperWindows() {
        for w in wallpaperWindows { w.hide() }
        wallpaperWindows.removeAll()
        rdLog("animated wallpaper: hidden")
    }

    // MARK: - Status menu actions

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
            // Build the recorder views with their on-change callbacks
            // wired to update HotkeyManager registration in real time.
            let activate = HotkeyRecorderView(
                storageKey: activateHotkeyKey,
                onChange: { [weak self] cfg in self?.activateHotkeyChanged(cfg) }
            )
            let screenshot = HotkeyRecorderView(
                storageKey: screenshotHotkeyKey,
                onChange: { [weak self] cfg in self?.screenshotHotkeyChanged(cfg) }
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
