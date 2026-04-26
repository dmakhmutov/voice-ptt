import Foundation

struct UpdateInfo {
    let version: String        // "0.2"
    let pageURL: URL           // GitHub release page
    let publishedAt: Date
    let body: String           // release notes
}

/// Polls GitHub Releases API for `dmakhmutov/voice-ptt` and compares the
/// latest tag against our own `CFBundleShortVersionString`. We don't auto-
/// install — finding an update just surfaces a banner + notification, the
/// user clicks through to the Releases page and drags the new `.app` over
/// the old one. That's enough for a personal-scale tool.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Status {
        case unknown
        case checking
        case upToDate(String)              // current version
        case updateAvailable(UpdateInfo)
        case error(String)
    }

    @Published var status: Status = .unknown

    private let endpoint = URL(string: "https://api.github.com/repos/dmakhmutov/voice-ptt/releases/latest")!
    private let lastCheckKey = "updateChecker.lastCheckAt"
    /// 24h between automatic checks. Manual "Check now" bypasses this.
    private let staleAfter: TimeInterval = 24 * 60 * 60

    var ownVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    func check() async {
        status = .checking
        do {
            var req = URLRequest(url: endpoint)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: req)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURLString = json["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString) else {
                status = .error("Could not parse GitHub response")
                return
            }
            let body = (json["body"] as? String) ?? ""
            let publishedAt = (json["published_at"] as? String)
                .flatMap(ISO8601DateFormatter().date(from:)) ?? Date()

            let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            if latest.compare(ownVersion, options: .numeric) == .orderedDescending {
                status = .updateAvailable(UpdateInfo(
                    version: latest,
                    pageURL: htmlURL,
                    publishedAt: publishedAt,
                    body: body
                ))
            } else {
                status = .upToDate(ownVersion)
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Honors a 24h cool-down. Called at app start so we don't hammer the API.
    func checkIfStale() async {
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < staleAfter {
            return
        }
        await check()
    }
}
