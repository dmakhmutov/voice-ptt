import AVFoundation
import Foundation

/// Records mic audio on demand and resamples to 16 kHz mono Float32.
///
/// We allocate the AVAudioEngine **only while recording** — the moment a
/// long-lived `AVAudioEngine` instance exists in our process, macOS routes
/// the AirPods media-remote button (Play/Pause) into our audio session
/// and the user can't pause whatever video they're watching. Creating
/// and tearing down the engine per session keeps the AirPods button free
/// while we're idle.
final class AudioRecorder {
    enum RecorderError: Error {
        case formatUnavailable
        case converterUnavailable
        case engineStartFailed(Error)
    }

    private let targetSampleRate: Double = 16_000
    private let queue = DispatchQueue(label: "voiceptt.audio")

    private var engine: AVAudioEngine?
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var isRunning = false

    func start() throws {
        guard !isRunning else { return }
        samples.removeAll(keepingCapacity: true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { throw RecorderError.formatUnavailable }
        targetFormat = target

        guard let conv = AVAudioConverter(from: inputFormat, to: target) else {
            throw RecorderError.converterUnavailable
        }
        converter = conv

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            self.engine = engine
            isRunning = true
        } catch {
            throw RecorderError.engineStartFailed(error)
        }
    }

    func stop() -> [Float] {
        guard isRunning, let engine else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Drop the engine entirely so the audio device is fully released.
        // Otherwise AirPods stay in headset-mode-ish state and their
        // Play/Pause button keeps routing into our (idle) session.
        self.engine = nil
        converter = nil
        targetFormat = nil
        isRunning = false
        return queue.sync { samples }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil,
              let channelData = outBuffer.floatChannelData?[0] else { return }
        let count = Int(outBuffer.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channelData, count: count))
        queue.sync { samples.append(contentsOf: chunk) }
    }
}
