import AppKit
import WebKit
import UniformTypeIdentifiers

/// Capture the current rain frame from a WebView's WebGL canvas. Saves
/// as PNG to `~/Pictures/Rainy Day/screenshot-TIMESTAMP.png`.
///
/// Uses `canvas.toDataURL('image/png')` from JS — works because we
/// monkey-patch `HTMLCanvasElement.getContext` in `index.html` to force
/// `preserveDrawingBuffer: true`. Without that flag the WebGL backbuffer
/// is cleared after each frame and toDataURL would return blank pixels.
enum Screenshot {

    /// Capture from the most-likely-active screensaver window's webView.
    /// `webView` should be the one tied to the screen the user is
    /// currently on; AppDelegate picks the appropriate one.
    static func capture(from webView: WKWebView) {
        let js = "document.getElementById('rain').toDataURL('image/png')"
        webView.evaluateJavaScript(js) { result, error in
            if let error = error { rdLog("screenshot: JS error \(error.localizedDescription)"); return }
            guard let str = result as? String,
                  let comma = str.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(str[str.index(after: comma)...])) else {
                rdLog("screenshot: data parse failed")
                return
            }
            saveToPicturesFolder(data)
        }
    }

    private static func saveToPicturesFolder(_ pngData: Data) {
        let fm = FileManager.default
        guard let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask).first else {
            rdLog("screenshot: no Pictures dir")
            return
        }
        let dir = pictures.appendingPathComponent("Rainy Day", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "screenshot-\(formatter.string(from: Date())).png"
        let url = dir.appendingPathComponent(filename)

        do {
            try pngData.write(to: url)
            rdLog("screenshot: saved \(url.path)")
        } catch {
            rdLog("screenshot: write failed \(error.localizedDescription)")
        }
    }
}
