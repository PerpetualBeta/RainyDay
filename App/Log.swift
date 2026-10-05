import Foundation

// Diagnostic logging — off by default, enabled per-machine via:
//
//   defaults write cc.jorviksoftware.RainyDay debugLogging -bool YES
//   defaults delete cc.jorviksoftware.RainyDay debugLogging   # turn off
//
// When on, timestamped lines are appended to
//   ~/Library/Logs/Rainy Day/rainyday.log
// and the lines before the last rotation are kept in rainyday.log.1.
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

private let rdPreviousLogPath = rdLogPath + ".1"

/// Rotate once the live log passes this many bytes, keeping one previous
/// generation, so the logs can never occupy more than twice this figure.
/// 4 MB by default, as in the other Jorvik apps. Until 2026-10-05 the log grew
/// for ever and had reached 11.6 MB. A knob for a long diagnostic session:
///
///     defaults write cc.jorviksoftware.RainyDay debugLogMaxBytes -int 20971520
private var rdLogMaxBytes: Int {
    let stored = UserDefaults.standard.integer(forKey: "debugLogMaxBytes")
    return stored > 0 ? stored : 4 * 1024 * 1024
}

func rdLog(_ msg: String) {
    guard UserDefaults.standard.bool(forKey: "debugLogging") else { return }
    let stamp = rdLogFmt.string(from: Date())
    let limit = rdLogMaxBytes
    rdLogQueue.async {
        rdAppend("\(stamp)  \(msg)\n")
        // Only the app writes this log, and only on this serial queue, so the
        // size read here is the file just written to, and nothing can rotate
        // it in between.
        var info = stat()
        guard stat(rdLogPath, &info) == 0, info.st_size >= limit else { return }
        unlink(rdPreviousLogPath)
        guard rename(rdLogPath, rdPreviousLogPath) == 0 else { return }
        rdAppend("\(stamp)  log rotated at \(info.st_size) bytes; the lines before this are in rainyday.log.1\n")
    }
}

/// Appends one line. Runs on `rdLogQueue` only.
private func rdAppend(_ line: String) {
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
