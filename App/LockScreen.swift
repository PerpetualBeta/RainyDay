import Foundation
import Carbon.HIToolbox
import CoreGraphics

/// Locks the screen by posting macOS's built-in Lock Screen keyboard
/// shortcut (⌃⌘Q) directly via `CGEvent`. We previously shelled out to
/// `osascript -e 'tell application "System Events" to keystroke "q"
/// using {control down, command down}'`, which worked but cost
/// 200–400ms of subprocess + AppleScript + System Events startup
/// before loginwindow ever saw the keystroke. That gap was visible:
/// the saver stayed up but the lock UI took a beat to overlay it.
///
/// CGEvent posts straight at the session event tap. Loginwindow gets
/// the keystroke essentially immediately, the lock UI animates in
/// over the still-rendering saver, and the visual flow now matches a
/// native `.saver` bundle — saver running underneath, auth prompt on
/// top, both dismiss together when the user authenticates.
///
/// Still requires Accessibility — CGEvents posted at the session tap
/// go through the same TCC trust check the AppleScript path did. The
/// Settings → Permissions toggle and the system prompt are unchanged.
enum LockScreen {
    static func lock() {
        let src = CGEventSource(stateID: .hidSystemState)
        let q = CGKeyCode(kVK_ANSI_Q)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: q, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: q, keyDown: false) else {
            rdLog("LockScreen: CGEvent creation failed")
            return
        }
        let mods: CGEventFlags = [.maskCommand, .maskControl]
        down.flags = mods
        up.flags = mods
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        rdLog("LockScreen: posted ⌃⌘Q via CGEvent")
    }
}
