import AppKit

/// Manages the user-modifiable folder of background images at
/// `~/Library/Application Support/Rainy Day/Backgrounds/`.
///
/// On first launch (or whenever the folder is empty), seeds the folder
/// with the six bundled defaults that ship inside the app. After that,
/// the user can drop, remove, or replace any image files they like —
/// the saver picks up whatever's there each time it activates.
enum BackgroundsStore {

    /// Image extensions raindrop-fx + WebKit can decode.
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]

    static var folderURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Rainy Day", isDirectory: true)
            .appendingPathComponent("Backgrounds", isDirectory: true)
    }

    /// Ensure the folder exists. If it's empty, copy the bundled
    /// defaults into it. Idempotent.
    static func ensureSeeded() {
        let fm = FileManager.default
        let dir = folderURL
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            rdLog("BackgroundsStore: createDirectory failed — \(error.localizedDescription)")
            return
        }
        if !images(in: dir).isEmpty { return }
        seedFromBundle(into: dir)
    }

    /// All image files currently in the user's backgrounds folder,
    /// sorted by name for deterministic cycling order.
    static func currentImages() -> [URL] {
        images(in: folderURL).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Reveal the backgrounds folder in Finder so the user can add
    /// or remove images.
    static func revealInFinder() {
        NSWorkspace.shared.open(folderURL)
    }

    // MARK: - Private

    private static func images(in url: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return contents.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    private static func seedFromBundle(into dir: URL) {
        guard let bundleBackgrounds = Bundle.main.resourceURL?
            .appendingPathComponent("backgrounds", isDirectory: true) else {
            rdLog("BackgroundsStore: no bundle backgrounds dir — skipping seed")
            return
        }
        let fm = FileManager.default
        let seeds = images(in: bundleBackgrounds)
        for src in seeds {
            let dst = dir.appendingPathComponent(src.lastPathComponent)
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                rdLog("BackgroundsStore: seed copy failed for \(src.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        rdLog("BackgroundsStore: seeded \(seeds.count) defaults into \(dir.path)")
    }
}
