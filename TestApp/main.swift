import AppKit
import ScreenSaver

// ---------------------------------------------------------------------------
// Standalone NSWindow harness for rapid iteration. Instantiates the same
// RainyDayView the .saver bundle uses, hosted in an NSWindow. Run via:
//
//   make run
//
// Bundle.main resolves to RainyDayTest.app, which has Resources/ copied
// from the project's Resources/ tree at build time — so loadFileURL finds
// index.html the same way it would inside the .saver.
// ---------------------------------------------------------------------------

final class TestAppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var saverView: RainyDayView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 200, y: 200, width: 1280, height: 800)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Rainy Day — Test"
        guard let view = RainyDayView(frame: window.contentView!.bounds, isPreview: false) else {
            NSApp.terminate(nil)
            return
        }
        view.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(view)
        saverView = view

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = TestAppDelegate()
app.delegate = delegate
app.run()
