import Foundation
import FluidAudio

final class Transcriber {
    enum State {
        case unloaded
        case loading
        case ready
        case failed(Error)
    }

    private(set) var state: State = .unloaded
    private var asr: AsrManager?

    func load() async {
        state = .loading
        do {
            let models = try await AsrModels.downloadAndLoad()
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            self.asr = manager
            state = .ready
            NSLog("VoicePTT: ASR ready")
        } catch {
            state = .failed(error)
            NSLog("VoicePTT: ASR load failed: \(error)")
        }
    }

    func transcribe(_ samples: [Float]) async -> String? {
        guard case .ready = state, let asr else { return nil }
        guard !samples.isEmpty else { return nil }
        do {
            let result = try await asr.transcribe(samples)
            return result.text
        } catch {
            NSLog("VoicePTT: transcribe error: \(error)")
            return nil
        }
    }
}
