import Foundation
import AppKit

enum UpdateCheckInterval: Int, CaseIterable, Identifiable {
    case daily = 86400
    case weekly = 604800
    case monthly = 2592000
    case never = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every 30 days"
        case .never: "Never"
        }
    }
}

enum UpdateStatus: Equatable {
    case unknown
    case checking
    case upToDate(version: String)
    case available(version: String, url: String)
    case downloading(progress: String)
    case error(String)
}

@Observable
final class JorvikUpdateChecker {
    let repoName: String

    var status: UpdateStatus = .unknown
    var checkInterval: UpdateCheckInterval {
        didSet { UserDefaults.standard.set(checkInterval.rawValue, forKey: "updateCheckInterval") }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    init(repoName: String) {
        self.repoName = repoName
        let stored = UserDefaults.standard.integer(forKey: "updateCheckInterval")
        self.checkInterval = UpdateCheckInterval(rawValue: stored) ?? .weekly
    }

    private var scheduledTimer: Timer?

    func checkOnSchedule() {
        // Check immediately if enough time has elapsed
        checkIfDue()

        // Schedule a repeating timer to re-check periodically while the app
        // is running. Menu bar utilities often run for days without relaunch,
        // so the launch-time check alone is insufficient.
        scheduledTimer?.invalidate()
        guard checkInterval != .never else { return }
        scheduledTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        guard checkInterval != .never else { return }

        let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        let elapsed = Date().timeIntervalSince(lastCheck)

        if elapsed >= Double(checkInterval.rawValue) {
            Task { await checkNow() }
        }
    }

    @MainActor
    func checkNow() async {
        status = .checking

        guard let url = URL(string: "https://api.github.com/repos/PerpetualBeta/\(repoName)/releases/latest") else {
            status = .error("Invalid repo URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                status = .error("GitHub API returned an error")
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else {
                status = .error("Could not parse GitHub response")
                return
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")

            if isNewer(remote: remoteVersion, local: currentVersion) {
                status = .available(version: remoteVersion, url: htmlURL)
            } else {
                status = .upToDate(version: currentVersion)
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func openReleasePage() {
        if case .available(_, let url) = status, let releaseURL = URL(string: url) {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    // MARK: - Auto-install (REMOVED)
    //
    // The previous in-process auto-install path downloaded a zip from
    // GitHub and ran shell scripts to swap the bundle, with no signature
    // verification — neither codesign nor any custom signature. Sparkle
    // 2.x now owns the update flow end-to-end, including EdDSA
    // verification of every downloaded payload via SUPublicEDKey in
    // Info.plist. Any auto-install behaviour comes from Sparkle alone.

    // MARK: - Version comparison

    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
