import Foundation

// Diagnostic logging — timestamped lines to /tmp/rainyday.log. Always
// on while we're stabilising; can be gated on a defaults flag later.

private let rdLogPath = "/tmp/rainyday.log"
private let rdLogQueue = DispatchQueue(label: "cc.jorviksoftware.RainyDay.log")
private let rdLogFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

func rdLog(_ msg: String) {
    let line = "\(rdLogFmt.string(from: Date()))  \(msg)\n"
    rdLogQueue.async {
        guard let data = line.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: rdLogPath) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: rdLogPath, contents: data)
        }
    }
}
