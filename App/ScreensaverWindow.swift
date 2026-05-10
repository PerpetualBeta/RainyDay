import AppKit
import WebKit

/// A fullscreen, top-level window covering one display, hosting a
/// WKWebView running raindrop-fx. Dismisses on any mouse or key event.
///
/// One instance per `NSScreen`. When activated, every `ScreensaverWindow`
/// covers its respective display; together they form a system-wide
/// screensaver effect.
///
/// Composition rather than NSWindow subclassing — NSWindow's required
/// designated initializer signature makes subclassing fiddly, and we
/// don't actually need to override any window methods.
final class ScreensaverWindow {

    private let window: NSWindow
    private(set) var webView: WKWebView!
    private var eventMonitor: Any?
    private let onDismiss: () -> Void
    let screen: NSScreen

    init(screen: NSScreen, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.screen = screen
        self.window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // Screensaver level — above all normal windows including
        // floating panels. Black opaque background so any letterboxing
        // around the WebView is invisible.
        window.level = .screenSaver
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        // Stationary across Spaces; visible on every Space; not in
        // window cycle (cmd+`).
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        configureWebView(on: screen)
    }

    private func configureWebView(on screen: NSScreen) {
        let config = WKWebViewConfiguration()
        // Required so the file:// page can read its file:// background
        // images into a canvas without tainting it (raindrop-fx's WebGL
        // upload + the toDataURL screenshot path both depend on the
        // canvas being clean). developerExtrasEnabled is intentionally
        // NOT set — the saver dismisses on any mouse event so devtools
        // would be unreachable in normal use anyway.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Inject runtime config BEFORE the page's main scripts run so
        // index.html sees window.RAINY_DAY_CONFIG synchronously when
        // it executes. JSON-serialised rather than string-interpolated
        // — a path containing a `"` or `\` would otherwise break the
        // generated JS literal (URL percent-encoding usually saves us
        // here, but JSON is the right tool and removes the dependency
        // on URL escaping rules never changing).
        config.userContentController.addUserScript(
            WKUserScript(source: Self.makeConfigScript(),
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true))

        let container = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        container.wantsLayer = true
        window.contentView = container

        webView = WKWebView(frame: container.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        // Transparent WebView so the window's black background shows
        // during the brief window between window-show and the page's
        // first paint. With drawsBackground=true the WebView paints
        // its default white during load, producing a jarring flash
        // before raindrop-fx draws its first frame.
        webView.setValue(false, forKey: "drawsBackground")
        container.addSubview(webView)

        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            rdLog("ERROR: index.html not found in app bundle")
            return
        }
        // Read access must encompass BOTH the bundle's Resources/ (for
        // raindrop-fx.bundle.js) AND ~/Library/Application Support/
        // Rainy Day/Backgrounds/ (for the photo files). They live in
        // unrelated parts of the filesystem, so we open access to the
        // root — acceptable for a trusted-content screensaver where
        // the only resources the JS ever loads are the ones we
        // explicitly inject via WKUserScript.
        webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        rdLog("ScreensaverWindow loaded \(indexURL.lastPathComponent) on \(screen.localizedName)")
    }

    func activate() {
        window.makeKeyAndOrderFront(nil)
        // Hide the cursor while the saver is running. Counter-balanced
        // with `unhide()` in `deactivate()`; the AppKit API maintains
        // an internal hide-count, so multi-window activations across
        // multiple displays balance correctly.
        NSCursor.hide()
        // Grace period before installing the dismiss monitor. When
        // the user activates via a global hotkey (⌃⌥⌘R or similar),
        // they release the modifier keys an instant after the press.
        // That release fires .flagsChanged, which without this delay
        // would immediately dismiss the screensaver we just opened.
        // 600ms is comfortably longer than any reasonable key-release
        // and short enough that an intentional dismiss feels instant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            // Note: .flagsChanged is intentionally OMITTED. When the
            // user fires a Carbon-registered global hotkey (activate,
            // screenshot), Carbon consumes the keyDown but the
            // subsequent modifier-up still flows through NSEvent. If
            // we listened to .flagsChanged we'd dismiss the saver
            // every time the user uses a hotkey while it's running.
            self.eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown, .rightMouseDown,
                           .otherMouseDown, .scrollWheel, .keyDown]
            ) { [weak self] event in
                self?.onDismiss()
                return nil   // swallow — we're dismissing
            }
        }
    }

    func deactivate() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
        // Balance the activate-side hide(). AppKit maintains a
        // hide-count internally; for N activated windows we issue
        // N hides + N unhides, leaving the global state correct.
        NSCursor.unhide()
        window.orderOut(nil)
    }

    /// Build the WKUserScript source that defines `window.RAINY_DAY_CONFIG`.
    /// Shared with `WallpaperWindow` — both windows want identical config.
    static func makeConfigScript() -> String {
        let cycleMinutes = max(1, min(30, UserDefaults.standard.integer(forKey: "cycleMinutes")))
        let cycleMs = (cycleMinutes > 0 ? cycleMinutes : 5) * 60 * 1000
        let payload: [String: Any] = [
            "cycleMs": cycleMs,
            "backgrounds": BackgroundsStore.currentImages().map { $0.absoluteString }
        ]
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = #"{"cycleMs":300000,"backgrounds":[]}"#
        }
        return "window.RAINY_DAY_CONFIG = \(json);"
    }
}
