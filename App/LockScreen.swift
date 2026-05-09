import Foundation

/// Locks the screen by simulating macOS's built-in Lock Screen
/// keyboard shortcut (⌃⌘Q). The CGSession CLI tool we'd previously
/// have used is gone in macOS 26 — only the header file remains.
///
/// First call triggers an Accessibility permission prompt because
/// AppleScript's `System Events` needs permission to post keystrokes
/// to other apps. Once granted, it's silent thereafter.
///
/// Asynchronous: returns immediately; the lock dialog appears a
/// moment later.
enum LockScreen {
    static func lock() {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [
            "-e",
            "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        ]
        do {
            try task.run()
            rdLog("LockScreen: posted ⌃⌘Q via osascript")
        } catch {
            rdLog("LockScreen: failed — \(error.localizedDescription)")
        }
    }
}
