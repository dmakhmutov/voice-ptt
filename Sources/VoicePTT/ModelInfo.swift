import Foundation

/// Single source of truth for everything user-visible about the speech-recognition
/// model: name, expected size, where it lives. When we switch the underlying model
/// (e.g. Parakeet v3 → v4, or to a different engine entirely) this is the only
/// place that needs editing — the UI, status hints, progress meter, and HUD copy
/// all read from here.
enum ModelInfo {
    /// Short, human-readable name shown in UI.
    static let displayName = "Parakeet"

    /// Approximate full-download size in megabytes. Used as the denominator for
    /// the on-launch download progress meter and copy in messages. Update when
    /// switching to a model with a noticeably different on-disk footprint.
    static let expectedSizeMB: Int64 = 500

    /// Pre-formatted size string shown in messages, e.g. "Parakeet (~500 MB)".
    static var sizeDescription: String { "~\(expectedSizeMB) MB" }

    /// Human-readable identifier used in messages where the engine name matters,
    /// e.g. status hints. Format: "Parakeet (~500 MB)".
    static var nameAndSize: String { "\(displayName) (\(sizeDescription))" }
}
