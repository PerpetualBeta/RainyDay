import ScreenSaver
import AppKit
import WebKit

/// Principal class. macOS instantiates one of these per attached display when
/// the screensaver activates. Each instance hosts its own `WKWebView`
/// rendering the bundled `Resources/index.html` — which initialises
/// raindrop-fx (an MIT-licensed WebGL2 rain-on-glass effect by SardineFish,
/// vendored into the bundle as `raindrop-fx.bundle.js`).
///
/// The Swift side is intentionally tiny: load the HTML file from the bundle,
/// fill the screen, get out of the way. All animation, physics, and
/// rendering live in the WebGL context managed by the JS side.
@objc(RainyDayView)
public final class RainyDayView: ScreenSaverView {

    private var webView: WKWebView!

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        // The browser drives its own RAF loop at 60 Hz; we don't need
        // animateOneFrame to fire frequently. Setting a long interval
        // keeps macOS from forcing redraws.
        animationTimeInterval = 1.0
        configureWebView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0
        configureWebView()
    }

    // MARK: - WKWebView setup

    private func configureWebView() {
        let config = WKWebViewConfiguration()
        // Allow file:// resources to load sibling files (the HTML loads
        // raindrop-fx.bundle.js from the same directory).
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        // Don't paint the WebView's default white background — we want the
        // canvas itself to be the only thing rendered.
        webView.setValue(false, forKey: "drawsBackground")
        addSubview(webView)
        loadIndexHTML()
    }

    private func loadIndexHTML() {
        // `Bundle(for: type(of: self))` resolves to the .saver bundle when
        // hosted by legacyScreenSaver, or to the test app's bundle when
        // hosted directly. Both contain `Resources/index.html`.
        let bundle = Bundle(for: type(of: self))
        guard let indexURL = bundle.url(forResource: "index", withExtension: "html") else {
            // No index.html — fail visibly with a black screen rather
            // than crash. Should never happen if the bundle was built
            // correctly.
            return
        }
        // allowingReadAccessTo must be the directory so loads of sibling
        // resources (raindrop-fx.bundle.js) succeed.
        let resourcesDir = indexURL.deletingLastPathComponent()
        webView.loadFileURL(indexURL, allowingReadAccessTo: resourcesDir)
    }

    // MARK: - ScreenSaverView

    public override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        webView.frame = bounds
    }

    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}
