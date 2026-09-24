import AppKit
import SwiftUI
import ApplicationServices

/// Settings window for Rainy Day. Hosted by the standard
/// JorvikSettingsView wrapper which provides the title, "General"
/// section (Launch at Login), and Done button. App-specific sections
/// live in `RainyDaySettingsContent`.
final class SettingsWindow {

    let activateRecorder: JorvikHotkeyRow
    let screenshotRecorder: JorvikHotkeyRow

    init(activateRecorder: JorvikHotkeyRow, screenshotRecorder: JorvikHotkeyRow) {
        self.activateRecorder = activateRecorder
        self.screenshotRecorder = screenshotRecorder
    }

    func show() {
        JorvikSettingsView.showWindow(appName: "Rainy Day") {
            RainyDaySettingsContent(
                activateRecorder: self.activateRecorder,
                screenshotRecorder: self.screenshotRecorder
            )
        }
    }
}

// MARK: - App-specific settings sections

/// Per the Jorvik convention, sections appear top-to-bottom in the
/// order: Permissions → app-specific → General (Launch at Login,
/// auto-injected by JorvikSettingsView).
///
/// Rainy Day has no Permissions section, because it needs no permissions. See
/// the note in `body` — that section was removed on 2026-09-21 after the claim
/// it made was measured and found false.
struct RainyDaySettingsContent: View {

    let activateRecorder: JorvikHotkeyRow
    let screenshotRecorder: JorvikHotkeyRow

    @AppStorage("idleMinutes")        private var idleMinutes: Int = 5
    @AppStorage("cycleMinutes")       private var cycleMinutes: Int = 5
    @AppStorage("lockOnDismiss")      private var lockOnDismiss: Bool = false
    @AppStorage("animatedWallpaper")  private var animatedWallpaper: Bool = false
    @AppStorage("activationSuspended") private var activationSuspended: Bool = false
    /// The soonest of macOS's own idle timers, re-read when Settings opens
    /// and when the app becomes active again. See `macScreenLockNote`.
    @State private var macMinimumTrigger: (seconds: TimeInterval, cause: SystemScreenLockSettings.Cause)?

    // There is no Permissions section, and that is deliberate.
    //
    // This window used to carry one: an Accessibility row, a Grant Access
    // button, and the caption "Accessibility is required to lock the screen
    // when the saver dismisses." That was true for eight days in May, while the
    // lock was a synthesised ⌃⌘Q. It stopped being true on 2026-05-18 when the
    // lock became a `SACLockScreenImmediate` call into loginwindow, which asks
    // for no permission at all — and the section stayed for four more months.
    //
    // Measured 2026-09-21 with the grant revoked: the saver activated from its
    // hotkey and the lock confirmed 190ms later. Nothing here needs it. The app
    // has no global event monitors, no event taps and no AXUIElement calls —
    // the only three things that would.
    //
    // It is removed rather than reworded because the caption was not merely
    // wrong, it was the thing that obtained the privilege: it told the user the
    // permission was required and put a button next to the claim. A screensaver
    // does not ask for the right to read and synthesise input across every
    // other application, least of all for a job it does without it.
    //
    // `JorvikPermissionWatcher` stays in the vendored JorvikKit, untouched and
    // unreferenced — that set is kept byte-identical across the estate and
    // diverging one copy to delete a file nobody calls is the worse trade.
    var body: some View {
        MenuBarVisibilitySettings()

        Section("Activation") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Suspended")
                    Spacer()
                    Toggle("", isOn: $activationSuspended)
                        .labelsHidden()
                        .onChange(of: activationSuspended) { _, suspended in
                            rdLog(suspended ? "activation suspended from Settings" : "activation resumed from Settings")
                            // Written directly via @AppStorage, so the status
                            // item, which has no observer on the key itself,
                            // needs telling to update its icon and menu label.
                            NotificationCenter.default.post(name: .activationSuspendedChanged, object: nil)
                        }
                }
                Text("While suspended, Rainy Day will not activate on its own when idle. Activate Now still works, from the menu or its shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Idle timeout")
                    Spacer()
                    TextField("", value: $idleMinutes, formatter: Self.minutes(min: 1, max: 1440))
                        .labelsHidden()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("minutes")
                        .foregroundStyle(.secondary)
                }
                if let note = macScreenLockNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            activateRecorder
        }
        .onAppear { refreshMacScreenLockTimers() }
        // Nothing tells this app when a System Settings timer changes. Someone
        // who has just changed one comes back to this app to look, which makes
        // it active again, so re-read them then.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMacScreenLockTimers()
        }

        Section("On dismiss") {
            Toggle("Lock screen when dismissed", isOn: $lockOnDismiss)
        }

        Section("Capture") {
            VStack(alignment: .leading, spacing: 4) {
                screenshotRecorder
                Text("Saves to ~/Pictures/Rainy Day/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Backgrounds") {
            HStack {
                Text("Cycle every")
                Spacer()
                TextField("", value: $cycleMinutes, formatter: Self.minutes(min: 1, max: 30))
                    .labelsHidden()
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("minutes")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Backgrounds folder")
                    Spacer()
                    Button("Open") {
                        BackgroundsStore.revealInFinder()
                    }
                }
                Text("Drop JPG/PNG/HEIC files into the folder. An empty folder shows a notice instead of rain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Wallpaper") {
            // The label is its own Text and the Toggle is labelsHidden, rather than
            // Toggle("…", isOn:) — a control carrying its own label inside a VStack
            // loses the Form's label column, which is how Release Manager 2.0.40
            // shipped a row whose text field drew at zero width.
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Use as animated desktop wallpaper")
                    Spacer()
                    Toggle("", isOn: $animatedWallpaper)
                        .labelsHidden()
                }
                Text("Renders rain at the desktop layer behind icons and apps. Independent of screensaver activation; persists until you turn it off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Logged only when the summary changes, not on every refresh.
    private static var lastLoggedMacScreenLockSummary: String?

    private func refreshMacScreenLockTimers() {
        macMinimumTrigger = SystemScreenLockSettings.minimumTrigger
        let summary = SystemScreenLockSettings.summaryForLogging
        if summary != Self.lastLoggedMacScreenLockSummary {
            rdLog("macOS screen/display timers: \(summary)")
            Self.lastLoggedMacScreenLockSummary = summary
        }
    }

    /// A warning for the idle-timeout row, shown only when macOS's own screen
    /// saver, or the display-off timer that applies to this Mac, is set at or
    /// below the idle timeout. `nil`, so no note at all, otherwise. One whole
    /// sentence per cause, each naming the row as System Settings labels it.
    private var macScreenLockNote: String? {
        guard let trigger = macMinimumTrigger,
              Double(idleMinutes) * 60 >= trigger.seconds
        else { return nil }
        let minutes = Int((trigger.seconds / 60).rounded())
        switch trigger.cause {
        case .screensaver:
            return "“Start Screen Saver when inactive” is set to \(minutes) min in System Settings, so macOS’s own screen saver starts first and Rainy Day never does."
        case .displaySleep:
            return "“Turn display off when inactive” is set to \(minutes) min in System Settings, so the display goes dark before Rainy Day can start."
        case .displaySleepBattery:
            return "“Turn display off on battery when inactive” is set to \(minutes) min in System Settings. On battery, the display goes dark before Rainy Day can start."
        case .displaySleepACPower:
            return "“Turn display off on power adapter when inactive” is set to \(minutes) min in System Settings. On the power adapter, the display goes dark before Rainy Day can start."
        }
    }

    private static func minutes(min lo: Int, max hi: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = NSNumber(value: lo)
        f.maximum = NSNumber(value: hi)
        f.allowsFloats = false
        return f
    }
}
