import AppKit
import SwiftUI
import ApplicationServices

/// Settings window for Rainy Day. Hosted by the standard
/// JorvikSettingsView wrapper which provides the title, "General"
/// section (Launch at Login), and Done button. App-specific sections
/// live in `RainyDaySettingsContent`.
final class SettingsWindow {

    /// Stable JorvikUpdateChecker instance — kept around because
    /// JorvikSettingsView requires one as a parameter even though
    /// Sparkle now handles the actual update flow. Per the KB:
    /// "Leave the JorvikUpdateChecker instance in place; the lingering
    /// instance is inert."
    private let updateChecker = JorvikUpdateChecker(repoName: "RainyDay")

    let activateRecorder: HotkeyRecorderView
    let screenshotRecorder: HotkeyRecorderView

    init(activateRecorder: HotkeyRecorderView, screenshotRecorder: HotkeyRecorderView) {
        self.activateRecorder = activateRecorder
        self.screenshotRecorder = screenshotRecorder
    }

    func show() {
        JorvikSettingsView.showWindow(
            appName: "Rainy Day",
            updateChecker: updateChecker
        ) {
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
struct RainyDaySettingsContent: View {

    let activateRecorder: HotkeyRecorderView
    let screenshotRecorder: HotkeyRecorderView

    @AppStorage("idleMinutes")        private var idleMinutes: Int = 5
    @AppStorage("cycleMinutes")       private var cycleMinutes: Int = 5
    @AppStorage("lockOnDismiss")      private var lockOnDismiss: Bool = false
    @AppStorage("animatedWallpaper")  private var animatedWallpaper: Bool = false

    /// AXIsProcessTrusted flips immediately after the user grants
    /// access in System Settings, but SwiftUI doesn't see the change
    /// without a redraw trigger. Re-poll when the window becomes key.
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()

    var body: some View {
        Section("Permissions") {
            HStack {
                Text("Accessibility")
                Spacer()
                if accessibilityGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button("Grant Access") {
                        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                    }
                    .font(.caption)
                }
            }
            Text("Accessibility is required to lock the screen when the saver dismisses.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

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
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
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
