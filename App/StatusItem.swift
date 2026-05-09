import AppKit

/// Single user-visible touchpoint for the app — a small SF Symbol in
/// the menu bar. Click it for a menu of actions: activate the
/// screensaver immediately, open settings, check for updates, quit.
final class StatusItem {

    private var item: NSStatusItem!
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        configure()
    }

    private func configure() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // SF Symbol — light rain glyph. Template image so the
            // system tints it for the active appearance (light/dark).
            button.image = NSImage(systemSymbolName: "cloud.drizzle.fill",
                                    accessibilityDescription: "Rainy Day")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "About Rainy Day",
                     action: #selector(showAbout), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Activate Now",
                     action: #selector(activateNow), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…",
                     action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Check for Updates…",
                     action: #selector(checkForUpdates), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Rainy Day",
                     action: #selector(quit), keyEquivalent: "q")
            .target = self
        item.menu = menu
        self.item = item
    }

    @objc private func showAbout() {
        JorvikAboutView.showWindow(
            appName: "Rainy Day",
            repoName: "RainyDay",
            productPage: "screensavers/rainyday"
        )
    }

    @objc private func activateNow() {
        appDelegate?.activateNowFromMenu()
    }

    @objc private func openSettings() {
        appDelegate?.openSettings()
    }

    @objc private func checkForUpdates() {
        // Foreground the app so Sparkle's first dialog isn't hidden
        // behind whatever was previously frontmost.
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        appDelegate?.sparkleUpdater.checkForUpdates(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
