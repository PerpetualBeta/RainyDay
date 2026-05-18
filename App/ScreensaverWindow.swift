import AppKit
import WebKit

/// Container view that hides the cursor while the mouse is anywhere
/// inside its bounds.
///
/// Three complementary mechanisms — none of them are bulletproof on
/// their own under macOS Tahoe (26.x), so we layer all three:
///
/// 1. **Cursor rects** (`resetCursorRects` + `addCursorRect`). The
///    window-server-level mechanism. Works regardless of key-window
///    status, which is critical on a multi-display saver where only
///    one window is ever key. Tahoe respects cursor rects even at
///    `.screenSaver` window level.
/// 2. **`.activeAlways` tracking area** with `NSCursor.set()` on
///    enter/move/cursorUpdate. Belt-and-braces for the cursor-rect
///    path; also covers any window the tracking area has but no
///    cursor rect (shouldn't happen, but the cost of redundancy is
///    nil).
/// 3. **CG-level hide** via `CGDisplayHideCursor`, fired in
///    `ScreensaverWindow.activate()` after `NSApp.activate(...)` so
///    the LSUIElement app counts as frontmost long enough for the
///    call to stick. Hide is ref-counted; matched by `Show` in
///    `deactivate()`.
///
/// The 16×16 transparent NSCursor needs a genuinely-drawn
/// representation. `NSImage(size:)` alone creates an image with zero
/// representations — when handed to `NSCursor`, the cursor library
/// materialises a fallback that may not be transparent. `lockFocus` +
/// an explicit clear fill guarantees a transparent bitmap rep exists.
private final class CursorHidingView: NSView {
    static let invisible: NSCursor = {
        let img = NSImage(size: NSSize(width: 16, height: 16))
        img.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: img.size).fill()
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: .zero)
    }()

    private var trackingArea: NSTrackingArea?

    override func resetCursorRects() {
        // Window-server cursor rect — fires on every display the
        // window covers, independent of key-window status.
        discardCursorRects()
        addCursorRect(bounds, cursor: Self.invisible)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect,
                      .mouseEnteredAndExited, .mouseMoved,
                      .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        // Re-register cursor rects since bounds may have changed.
        window?.invalidateCursorRects(for: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        Self.invisible.set()
    }

    override func mouseEntered(with event: NSEvent) {
        Self.invisible.set()
    }

    override func mouseMoved(with event: NSEvent) {
        Self.invisible.set()
    }
}

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
        // NSWindow's screen: parameter interprets contentRect as RELATIVE
        // to that screen's origin — so passing screen.frame (already in
        // global coords) with screen: secondaryScreen double-applies the
        // offset and parks the window off-screen. Omit the hint and let
        // the global contentRect place the window itself.
        self.window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
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

        let container = CursorHidingView(frame: NSRect(origin: .zero, size: window.frame.size))
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

        // Tahoe (macOS 26.x) tightened the cursor-visibility policy —
        // neither the WebKit `cursor: none` rule nor `NSCursor.set()`
        // alone is reliable for an LSUIElement app at `.screenSaver`
        // window level. Activate the app so the CG-level hide call
        // counts as frontmost, then hide system-wide. The hide is
        // ref-counted (`CGDisplayHideCursor` increments an internal
        // counter); deactivate() decrements with `CGDisplayShowCursor`.
        // Activation here is brief and invisible to the user — the
        // saver covers the screen at the same moment.
        NSApp.activate(ignoringOtherApps: true)
        CGDisplayHideCursor(CGMainDisplayID())

        // Cursor hiding has three paths working together — see the
        // doc comment on `CursorHidingView` for the rationale. The
        // CG-level hide above is the strongest; cursor rects + the
        // CSS rule + tracking-area `NSCursor.set()` cover the
        // remaining gaps.
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
                guard let self = self else { return nil }
                // Remove the monitor BEFORE invoking dismiss. A
                // single mouse move generates a burst of mouseMoved
                // events; without this guard each one fires onDismiss
                // again, which (in the lock-on-dismiss path) calls
                // LockScreen.lock() and observeLockThenPause()
                // repeatedly inside the same millisecond. Observed in
                // the field: 13 lock attempts from one cursor flick.
                if let m = self.eventMonitor {
                    NSEvent.removeMonitor(m)
                    self.eventMonitor = nil
                }
                self.onDismiss()
                return nil   // swallow — we're dismissing
            }
        }
    }

    func deactivate() {
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
            eventMonitor = nil
        }
        // Match the `CGDisplayHideCursor` from `activate()`. Hide is
        // ref-counted — every hide must be paired with a show or
        // subsequent normal app activity won't see the cursor. The
        // CSS rule + cursor rects fall away naturally when the
        // window orders out, no extra cleanup needed for those.
        CGDisplayShowCursor(CGMainDisplayID())
        window.orderOut(nil)
    }

    /// Halt the WebGL render loop without tearing down the window.
    /// Used while the system lock screen is covering us — the saver
    /// windows are invisible under loginwindow, so there's no point
    /// burning GPU on rain nobody can see. The page exposes
    /// `window.rainyDayPause()` which calls `fx.stop()` (cancels the
    /// requestAnimationFrame loop). The whole window is torn down on
    /// unlock, so a paired resume isn't needed.
    func pauseAnimation() {
        webView?.evaluateJavaScript("window.rainyDayPause && window.rainyDayPause();", completionHandler: nil)
    }

    /// Build the WKUserScript source that defines `window.RAINY_DAY_CONFIG`.
    /// Shared with `WallpaperWindow` — both windows want identical config.
    static func makeConfigScript() -> String {
        // `cycleMinutes` reads cleanly because AppDelegate registers a
        // default of 5 at launch — `integer(forKey:)` returns 5 for an
        // unset key rather than 0. The clamp here is purely defensive
        // against a wildly-out-of-range value somehow getting written.
        let cycleMinutes = max(1, min(30, UserDefaults.standard.integer(forKey: "cycleMinutes")))
        let cycleMs = cycleMinutes * 60 * 1000
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
