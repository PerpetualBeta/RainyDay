import Foundation

// Diagnostic logging — off by default, enabled per-machine via:
//
//   defaults write cc.jorviksoftware.RainyDay debugLogging -bool YES
//   defaults delete cc.jorviksoftware.RainyDay debugLogging   # turn off
//
// When on, timestamped lines are appended to
//   ~/Library/Logs/Rainy Day/rainyday.log
// (per-user, owner-only directory — not /private/tmp, where a
// predictable filename invites a symlink-target-overwrite by any
// same-user process.) The flag is read once per call so toggling it
// takes effect on the next log line.

private let rdLogPath: String = {
    let logs = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("Rainy Day", isDirectory: true)
    try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    return logs.appendingPathComponent("rainyday.log").path
}()
private let rdLogQueue = DispatchQueue(label: "cc.jorviksoftware.RainyDay.log")
private let rdLogFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

func rdLog(_ msg: String) {
    guard UserDefaults.standard.bool(forKey: "debugLogging") else { return }
    let line = "\(rdLogFmt.string(from: Date()))  \(msg)\n"
    rdLogQueue.async {
        guard let data = line.data(using: .utf8) else { return }
        // O_NOFOLLOW: refuse to follow a symlink at this path. Combined
        // with the 0700 parent directory created above, this closes the
        // symlink-attack vector entirely.
        let fd = open(rdLogPath, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        data.withUnsafeBytes { buf in
            _ = write(fd, buf.baseAddress, buf.count)
        }
    }
}
