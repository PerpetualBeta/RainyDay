import AppKit

// Rainy Day — a rain-on-glass screensaver delivered as a regular .app
// rather than a .saver bundle.
//
// Why an app, not a saver: hosting WKWebView inside legacyScreenSaver's
// sandbox repeatedly pinned us against process suspension, removed SPI,
// and SCK occlusion edge cases. A regular .app runs WebKit at full
// speed, with no helper or IPC, and we get full control over when the
// screen takes over (idle threshold) and when it dismisses (any user
// input). The trade-off is the saver doesn't appear in System Settings'
// screensaver list — Jorvik users launch the app once and it auto-runs
// at login from then on.

let app = NSApplication.shared
// .accessory == LSUIElement: no Dock icon, no menu bar, no app switcher
// entry. The user never sees the app itself; only the screensaver
// window when idle.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
