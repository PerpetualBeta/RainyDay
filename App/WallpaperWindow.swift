import AppKit
import WebKit

/// Fullscreen window that renders raindrop-fx at the desktop layer —
/// behind app windows and desktop icons but above the actual macOS
/// wallpaper. Click-through (ignoresMouseEvents = true) so it never
/// intercepts user input.
///
/// One instance per `NSScreen` when the user has enabled animated
/// wallpaper. Lifecycle is independent of `ScreensaverWindow` — the
/// wallpaper persists across screensaver activations; the screensaver
/// simply covers it during idle dismissal.
final class WallpaperWindow {

    private let window: NSWindow
    private var webView: WKWebView!
    let screen: NSScreen

    init(screen: NSScreen) {
        self.screen = screen
        // See ScreensaverWindow: NSWindow's screen: hint makes contentRect
        // relative to that screen, double-applying the offset on the
        // secondary display. Drop the hint and let the global frame place
        // the window.
        self.window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Desktop level — below normal app windows, above the actual
        // macOS wallpaper. Desktop icons sit on top of us, which is
        // the natural layering for a "live wallpaper".
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        // Click-through. Mouse and keyboard never interact with us.
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        configureWebView()
    }

    private func configureWebView() {
        let config = WKWebViewConfiguration()
        // Same WebView-policy rationale as ScreensaverWindow:
        // allowFileAccessFromFileURLs lets the page draw file:// images
        // into a clean canvas; developerExtrasEnabled is OFF because
        // this window is click-through and unreachable for inspection.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Shared config-injection helper — JSON-serialised in
        // ScreensaverWindow.makeConfigScript() so a path with `"` or
        // `\` can't break out of the generated JS literal.
        config.userContentController.addUserScript(WKUserScript(
            source: ScreensaverWindow.makeConfigScript(),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let container = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        container.wantsLayer = true
        window.contentView = container

        webView = WKWebView(frame: container.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        container.addSubview(webView)

        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            rdLog("ERROR: index.html not found in app bundle (wallpaper)")
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        rdLog("WallpaperWindow loaded on \(screen.localizedName)")
    }

    func show() {
        window.orderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }
}
