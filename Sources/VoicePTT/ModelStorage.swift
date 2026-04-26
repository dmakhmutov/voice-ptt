import AppKit
import Foundation

/// Inspector + janitor for FluidAudio's model cache. FluidAudio downloads
/// models into `~/Library/Application Support/FluidAudio/Models/` and never
/// cleans them up — every version bump leaves the previous model behind
/// (see `ModelInfo.expectedSizeMB`). The Settings UI shows what's there and
/// lets the user nuke stale entries (or the whole cache; the active model
/// gets re-downloaded on next launch).
@MainActor
final class ModelStorage: ObservableObject {
    static let shared = ModelStorage()

    struct Entry: Identifiable, Hashable {
        let id: String      // path
        let name: String
        let size: Int64
    }

    @Published var entries: [Entry] = []
    @Published var totalSize: Int64 = 0

    var cacheURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }

    /// True if any model directory already exists in the cache (i.e. not the
    /// first run). Used to pick between "Downloading…" vs "Loading…" copy
    /// when the app starts.
    var hasAnyCachedModel: Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return false
        }
        return !contents.isEmpty
    }

    /// Total bytes currently inside the cache directory (sum across all
    /// subdirectories). Used to fake a download progress indicator while
    /// FluidAudio is fetching the model — its 0.8.x API doesn't expose
    /// real progress callbacks.
    func currentCacheBytes() -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: cacheURL,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            if let bytes = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                .totalFileAllocatedSize {
                total += Int64(bytes)
            }
        }
        return total
    }

    var cachePathDisplay: String {
        cacheURL.path.replacingOccurrences(
            of: NSHomeDirectory(),
            with: "~"
        )
    }

    func refresh() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: cacheURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            entries = []
            totalSize = 0
            return
        }
        let new = contents.map { url -> Entry in
            Entry(id: url.path, name: url.lastPathComponent, size: directorySize(at: url))
        }.sorted { $0.size > $1.size }
        entries = new
        totalSize = new.reduce(0) { $0 + $1.size }
    }

    func openInFinder() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: cacheURL.path) {
            try? fm.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(cacheURL)
    }

    func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(atPath: entry.id)
        refresh()
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: cacheURL)
        refresh()
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            if let bytes = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                .totalFileAllocatedSize {
                total += Int64(bytes)
            }
        }
        return total
    }
}
