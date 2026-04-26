import AVFoundation
import Foundation

final class AudioRecorder {
    enum RecorderError: Error {
        case formatUnavailable
        case converterUnavailable
        case engineStartFailed(Error)
    }

    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16_000
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var isRunning = false
    private let queue = DispatchQueue(label: "voiceptt.audio")

    func start() throws {
        guard !isRunning else { return }
        samples.removeAll(keepingCapacity: true)

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

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            throw RecorderError.engineStartFailed(error)
        }
    }

    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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
