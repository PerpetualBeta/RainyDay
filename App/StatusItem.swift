import AppKit

/// Single user-visible touchpoint for the app — a small SF Symbol in
/// the menu bar. Click it for a menu of actions: activate the
/// screensaver immediately, open settings, check for updates, quit.
final class StatusItem {

    private var item: NSStatusItem?
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        configure()
    }

    /// Remove the status item from the menu bar. Called when the user
    /// hides the icon via Settings. Leaves the display-change observer
    /// in place (its `applyIcon` is a no-op once `item` is nil), so a
    /// later re-show via a fresh `StatusItem` rebuilds cleanly.
    func remove() {
        if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func configure() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyIcon(to: item)

        // Redraw the status icon when the display configuration changes — the
        // menu bar's effective thickness can shrink (e.g. moving from a notched
        // display to an external one) and leave the pre-rendered glyph cropped.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let item = self.item else { return }
            self.applyIcon(to: item)
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

    /// SF Symbol — light rain glyph. Template image so the system tints
    /// it for the active appearance (light/dark).
    private func applyIcon(to item: NSStatusItem) {
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "cloud.drizzle.fill",
                                accessibilityDescription: "Rainy Day")
        button.image?.isTemplate = true
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
