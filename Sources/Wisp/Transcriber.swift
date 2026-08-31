import AVFoundation
import FluidAudio

/// Wraps FluidAudio's sliding-window Parakeet engine.
/// Transcription runs on the Neural Engine; audio never leaves the machine.
actor Transcriber {

    enum State { case cold, loading, ready, streaming }

    private(set) var state: State = .cold
    private var manager: SlidingWindowAsrManager?

    /// Downloads (first run only) and loads the Parakeet models.
    func prepare() async throws {
        guard state == .cold else { return }
        state = .loading
        do {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let manager = SlidingWindowAsrManager(config: .streaming)
            try await manager.loadModels(models)
            self.manager = manager
            state = .ready
        } catch {
            state = .cold
            throw WispError.modelsUnavailable(error.localizedDescription)
        }
    }

    var isReady: Bool { state == .ready || state == .streaming }

    /// Live partial results, for showing words in the HUD as they are recognised.
    func updates() async -> AsyncStream<SlidingWindowTranscriptionUpdate>? {
        guard let manager else { return nil }
        return await manager.transcriptionUpdates
    }

    func beginUtterance() async throws {
        guard let manager, state == .ready else { return }
        try? await manager.reset()
        try await manager.startStreaming()
        state = .streaming
    }

    func feed(_ buffer: AVAudioPCMBuffer) async {
        guard state == .streaming, let manager else { return }
        await manager.streamAudio(buffer)
    }

    /// Ends the utterance and returns the final transcript.
    func endUtterance() async -> String {
        guard state == .streaming, let manager else { return "" }
        state = .ready
        let text = (try? await manager.finish()) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func abort() async {
        guard let manager else { return }
        await manager.cancel()
        state = .ready
    }
}
