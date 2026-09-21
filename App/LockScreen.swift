import Foundation
import CoreGraphics

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

    /// Whether the login session is locked **right now**.
    ///
    /// Asking is not the same as being told, and this is the difference that
    /// four months of misleading logs turned on. `SACLockScreenImmediate`
    /// returns 0 whether it locked the screen or found it already locked, and
    /// `com.apple.screenIsLocked` is posted only on a *transition*. So when the
    /// display has already slept — and this Mac's screen-lock delay is
    /// immediate, which locks the session at that moment — the call succeeds,
    /// no notification is posted, and a listener waiting to be told concludes
    /// the lock failed. It did not. There was nothing left to do.
    ///
    /// Measured across three savers: every lock request made after the saver
    /// had been up longer than the display-sleep timeout failed to confirm,
    /// 19 of 19, going back to May. Under that threshold, 1.7%.
    ///
    /// `CGSSessionScreenIsLocked` is absent from the dictionary when unlocked
    /// rather than present-and-false, so a missing key means unlocked.
    static var screenIsLocked: Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return info["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
