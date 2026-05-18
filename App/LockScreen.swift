import Foundation

/// Locks the screen by calling `SACLockScreenImmediate` in
/// `/System/Library/PrivateFrameworks/login.framework`.
///
/// We previously synthesised `⌃⌘Q` via `CGEvent` posted at the session
/// event tap. That worked on Sonoma and earlier, but macOS Tahoe
/// (26.x) tightened the policy on synthesised system shortcuts — the
/// keystroke is consumed but loginwindow never receives it, so the
/// lock screen never appears. The dismiss observer then times out
/// after 4 seconds and tears the saver down without ever locking.
///
/// `SACLockScreenImmediate` is the IPC path Apple uses internally
/// (loginwindow's own private framework), and it's the canonical
/// approach used by Hammerspoon, Bear, and most other menu-bar lock
/// apps. It doesn't require Accessibility because we're not
/// synthesising a keystroke — we're telling loginwindow directly to
/// lock. Verified present in Tahoe via dlsym.
///
/// Private API caveat: Apple could remove or rename the symbol in a
/// future macOS. The fall-through path here logs the failure and
/// returns gracefully; the dismiss flow then proceeds without
/// locking (the saver still tears down on the timeout path in
/// observeLockThenPause).
enum LockScreen {
    private typealias SACLockFn = @convention(c) () -> Int32

    /// Resolved once at first access. Cached for the process lifetime —
    /// the framework + symbol don't change while we're running, and
    /// re-resolving on every lock call would be wasted dlopen/dlsym.
    private static let sacLockScreenImmediate: SACLockFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY),
              let sym = dlsym(handle, "SACLockScreenImmediate")
        else {
            return nil
        }
        return unsafeBitCast(sym, to: SACLockFn.self)
    }()

    static func lock() {
        guard let fn = sacLockScreenImmediate else {
            rdLog("LockScreen: SACLockScreenImmediate unavailable — lock skipped")
            return
        }
        let result = fn()
        rdLog("LockScreen: SACLockScreenImmediate → result=\(result)")
    }
}
