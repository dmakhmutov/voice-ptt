import AppKit
import Foundation

struct UpdateInfo {
    let version: String        // "0.2"
    let pageURL: URL           // GitHub release page (for "Open release page" fallback)
    let assetURL: URL?         // direct VoicePTT-X.Y.zip download URL
    let publishedAt: Date
    let body: String           // release notes
}

/// Polls GitHub Releases API for `dmakhmutov/voice-ptt` and compares the
/// latest tag against our own `CFBundleShortVersionString`. If a newer
/// version exists, can also download + install it in place.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Status {
        case unknown
        case checking
        case upToDate(String)
        case updateAvailable(UpdateInfo)
        case error(String)
    }

    enum InstallState {
        case idle
        case downloading
        case unzipping
        case relaunching
        case failed(String)
    }

    @Published var status: Status = .unknown
    @Published var installState: InstallState = .idle

    private let endpoint = URL(string: "https://api.github.com/repos/dmakhmutov/voice-ptt/releases/latest")!
    private let lastCheckKey = "updateChecker.lastCheckAt"
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

            // Find first .zip asset for direct install.
            var assetURL: URL? = nil
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                       let urlString = asset["browser_download_url"] as? String,
                       let url = URL(string: urlString) {
                        assetURL = url
                        break
                    }
                }
            }

            let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            if latest.compare(ownVersion, options: .numeric) == .orderedDescending {
                status = .updateAvailable(UpdateInfo(
                    version: latest,
                    pageURL: htmlURL,
                    assetURL: assetURL,
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

    func checkIfStale() async {
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < staleAfter {
            return
        }
        await check()
    }

    /// Downloads the .zip asset, unzips, swaps in the new `.app` bundle in
    /// place, and relaunches via a helper shell script. The current process
    /// terminates once the helper takes over.
    func downloadAndInstall(_ info: UpdateInfo) async {
        guard let assetURL = info.assetURL else {
            installState = .failed("No .zip asset attached to the release")
            return
        }

        installState = .downloading
        do {
            // Working dir under temp.
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("voiceptt-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zipURL = work.appendingPathComponent("VoicePTT.zip")

            // Download.
            let (downloaded, response) = try await URLSession.shared.download(from: assetURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                installState = .failed("Download HTTP \(http.statusCode)")
                return
            }
            try FileManager.default.moveItem(at: downloaded, to: zipURL)

            // Unzip via ditto (preserves macOS metadata + xattrs).
            installState = .unzipping
            let unzipDir = work.appendingPathComponent("unzipped")
            try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zipURL.path, unzipDir.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                installState = .failed("Unzip failed (\(unzip.terminationStatus))")
                return
            }

            let newApp = unzipDir.appendingPathComponent("VoicePTT.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                installState = .failed("VoicePTT.app not found inside the zip")
                return
            }

            // Hand off to a helper that waits for us to exit, swaps the bundle,
            // strips the quarantine xattr (so Gatekeeper doesn't complain on
            // the next launch), and relaunches.
            let pid = ProcessInfo.processInfo.processIdentifier
            let currentApp = Bundle.main.bundlePath
            let script = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            rm -rf '\(currentApp)'
            mv '\(newApp.path)' '\(currentApp)'
            xattr -dr com.apple.quarantine '\(currentApp)' 2>/dev/null || true
            sleep 0.3
            open '\(currentApp)'
            """

            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/sh")
            helper.arguments = ["-c", script]
            try helper.run()

            installState = .relaunching
            // Give the UI a beat to render "Restarting…" before we go down.
            try? await Task.sleep(nanoseconds: 250_000_000)
            NSApplication.shared.terminate(nil)
        } catch {
            installState = .failed(error.localizedDescription)
        }
    }
}
