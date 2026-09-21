import AppKit
import SwiftUI
import ApplicationServices

/// Settings window for Rainy Day. Hosted by the standard
/// JorvikSettingsView wrapper which provides the title, "General"
/// section (Launch at Login), and Done button. App-specific sections
/// live in `RainyDaySettingsContent`.
final class SettingsWindow {

    let activateRecorder: HotkeyRecorderView
    let screenshotRecorder: HotkeyRecorderView

    init(activateRecorder: HotkeyRecorderView, screenshotRecorder: HotkeyRecorderView) {
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

    let activateRecorder: HotkeyRecorderView
    let screenshotRecorder: HotkeyRecorderView

    @AppStorage("idleMinutes")        private var idleMinutes: Int = 5
    @AppStorage("cycleMinutes")       private var cycleMinutes: Int = 5
    @AppStorage("lockOnDismiss")      private var lockOnDismiss: Bool = false
    @AppStorage("animatedWallpaper")  private var animatedWallpaper: Bool = false

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
            HStack {
                Text("Idle timeout:")
                TextField("", value: $idleMinutes, formatter: Self.minutes(min: 1, max: 1440))
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("minutes")
                Spacer()
            }
            HStack {
                Text("Activate now:")
                activateRecorder
                    .frame(width: 180, height: 24)
                Spacer()
            }
        }

        Section("On dismiss") {
            Toggle("Lock screen when dismissed", isOn: $lockOnDismiss)
        }

        Section("Capture") {
            HStack {
                Text("Screenshot:")
                screenshotRecorder
                    .frame(width: 180, height: 24)
                Spacer()
            }
            Text("Saves to ~/Pictures/Rainy Day/")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Backgrounds") {
            HStack {
                Text("Cycle every:")
                TextField("", value: $cycleMinutes, formatter: Self.minutes(min: 1, max: 30))
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("minutes")
                Spacer()
            }
            HStack {
                Button("Open Backgrounds Folder") {
                    BackgroundsStore.revealInFinder()
                }
                Spacer()
            }
            Text("Drop JPG/PNG/HEIC files into the folder. Empty folder shows a notice instead of rain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Wallpaper") {
            Toggle("Use as animated desktop wallpaper", isOn: $animatedWallpaper)
            Text("Renders rain at the desktop layer behind icons and apps. Independent of screensaver activation; persists until you turn it off.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
