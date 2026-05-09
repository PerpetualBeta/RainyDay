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
        self.window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
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
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Same config-injection pattern as ScreensaverWindow — read
        // user-configured cycle time and the live backgrounds list at
        // window-creation time.
        let cycleMinutes = max(1, min(30, UserDefaults.standard.integer(forKey: "cycleMinutes")))
        let cycleMs = (cycleMinutes > 0 ? cycleMinutes : 5) * 60 * 1000
        let bgURLs = BackgroundsStore.currentImages()
            .map { "\"\($0.absoluteString)\"" }
            .joined(separator: ", ")
        let injected = """
        window.RAINY_DAY_CONFIG = {
            cycleMs: \(cycleMs),
            backgrounds: [\(bgURLs)]
        };
        """
        config.userContentController.addUserScript(WKUserScript(
            source: injected, injectionTime: .atDocumentStart, forMainFrameOnly: true))

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
