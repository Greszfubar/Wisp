import AVFoundation
import Accelerate

/// Taps the default input device and hands out copies of each buffer,
/// plus a smoothed level for the HUD meter.
final class AudioCapture {

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private(set) var isRunning = false
    private var smoothedLevel: Float = 0

    func start() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw WispError.noInputDevice
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            // The engine reuses its tap buffer, so anything handed downstream must be a copy.
            guard let copy = buffer.deepCopy() else { return }
            self.onBuffer?(copy)
            self.emitLevel(for: copy)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        isRunning = false
        smoothedLevel = 0
    }

    private func emitLevel(for buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(buffer.frameLength))

        // Map RMS onto a perceptual 0...1 range, then ease it so the meter doesn't strobe.
        let db = 20 * log10(max(rms, 1e-7))
        let normalized = max(0, min(1, (db + 50) / 50))
        smoothedLevel += (normalized - smoothedLevel) * 0.3
        let level = smoothedLevel
        DispatchQueue.main.async { self.onLevel?(level) }
    }
}

extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        copy.frameLength = frameLength
        let channels = Int(format.channelCount)
        let frames = Int(frameLength)

        if let src = floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channels { dst[ch].update(from: src[ch], count: frames) }
        } else if let src = int16ChannelData, let dst = copy.int16ChannelData {
            for ch in 0..<channels { dst[ch].update(from: src[ch], count: frames) }
        } else {
            return nil
        }
        return copy
    }
}

enum WispError: LocalizedError {
    case noInputDevice
    case modelsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone is available."
        case .modelsUnavailable(let detail):
            return "Speech models could not be loaded: \(detail)"
        }
    }
}

enum MicPermission {
    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func request() async -> Bool {
        if isAuthorized { return true }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
