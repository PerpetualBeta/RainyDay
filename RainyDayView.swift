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
public final class RainyDayView: ScreenSaverView, WKNavigationDelegate {

    private var webView: WKWebView!

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        // The browser drives its own RAF loop at 60 Hz; we don't need
        // animateOneFrame to fire frequently. Setting a long interval
        // keeps macOS from forcing redraws.
        animationTimeInterval = 1.0
        rdLog("init(frame:isPreview:) — frame=\(frame) preview=\(isPreview)")
        configureWebView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0
        rdLog("init(coder:)")
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
        webView.navigationDelegate = self
        // Don't paint the WebView's default white background — we want the
        // canvas itself to be the only thing rendered.
        webView.setValue(false, forKey: "drawsBackground")
        // Keep the WebContent process at foreground priority. Without this
        // SPI, legacyScreenSaver's host context flags the WebView as
        // background and macOS aggressively suspends WebContent (observed
        // 2026-05-08 — `markAllLayersVolatile` immediately on launch,
        // WebGL never starts, screen stays black). The setValue-via-KVC
        // form works on macOS 14+; the symbol is private but stable
        // (BetterDisplay, Yabai, Tampermonkey-for-Safari all rely on it).
        webView.setValue(true, forKey: "_alwaysRunsAtForegroundPriority")
        addSubview(webView)
        rdLog("webView created, configured (foreground priority on)")
        loadIndexHTML()
    }

    private func loadIndexHTML() {
        // `Bundle(for: type(of: self))` resolves to the .saver bundle when
        // hosted by legacyScreenSaver, or to the test app's bundle when
        // hosted directly. Both contain `Resources/index.html`.
        let bundle = Bundle(for: type(of: self))
        rdLog("bundle.bundlePath=\(bundle.bundlePath)")
        guard let indexURL = bundle.url(forResource: "index", withExtension: "html") else {
            rdLog("ERROR: index.html not found in bundle")
            return
        }
        let resourcesDir = indexURL.deletingLastPathComponent()
        rdLog("loadFileURL: \(indexURL.path)  readAccess=\(resourcesDir.path)")
        webView.loadFileURL(indexURL, allowingReadAccessTo: resourcesDir)
    }

    // MARK: - WKNavigationDelegate (diagnostics only)

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        rdLog("didFinish navigation — page loaded")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        rdLog("didFail navigation: \(error.localizedDescription)")
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        rdLog("didFailProvisionalNavigation: \(error.localizedDescription)")
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        rdLog("WebContent process terminated — reloading")
        loadIndexHTML()
    }

    // MARK: - ScreenSaverView

    public override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        webView.frame = bounds
    }

    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}

// MARK: - Diagnostic logging
//
// Writes timestamped lines to /tmp/rainyday.log. Always-on for now while
// we're stabilising the saver-host integration; once the screensaver runs
// reliably in legacyScreenSaver this can be gated on a defaults flag the
// way ActiveSpace's logger is.

private let rdLogPath = "/tmp/rainyday.log"
private let rdLogQueue = DispatchQueue(label: "cc.jorviksoftware.RainyDay.log")
private let rdLogFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

func rdLog(_ msg: String) {
    let line = "\(rdLogFmt.string(from: Date()))  \(msg)\n"
    rdLogQueue.async {
        guard let data = line.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: rdLogPath) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: rdLogPath, contents: data)
        }
    }
}
