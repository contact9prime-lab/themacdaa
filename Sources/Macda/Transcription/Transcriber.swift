import Foundation

protocol Transcriber: Sendable {
    func transcribe(_ chunk: AudioChunk) async throws -> String
}

enum TranscriberError: LocalizedError {
    case missingConfig(String)
    case http(Int, String)
    case decode(String)
    case process(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig(let m): return m
        case .http(let code, let m): return "HTTP \(code): \(m)"
        case .decode(let m): return "Decode error: \(m)"
        case .process(let m): return m
        }
    }
}

/// Routes audio chunks to the configured backend, capping parallelism so the
/// machine isn't swamped when several chunks finish at once.
final class TranscriptionPipeline {
    private var transcriber: Transcriber = NullTranscriber()
    private var semaphore = AsyncSemaphore(value: 3)

    /// Reports the reason a chunk failed to transcribe (model not found, etc.).
    var onError: ((String) -> Void)?

    func configure(with settings: Settings) {
        semaphore = AsyncSemaphore(value: settings.parallelTranscriptions)
        switch settings.transcriptionProvider {
        case .ollamaAudio:
            let model = settings.ollamaTranscribeModel.isEmpty ? settings.ollamaModel : settings.ollamaTranscribeModel
            transcriber = OllamaAudioTranscriber(baseURL: settings.ollamaBaseURL, model: model)
        case .whisperCpp:
            transcriber = WhisperCppTranscriber(binary: settings.whisperCppBinaryPath,
                                                model: settings.whisperModelPath)
        case .openAI:
            transcriber = OpenAITranscriber(apiKey: settings.openAIKey,
                                            model: settings.openAITranscribeModel)
        case .gemini:
            transcriber = GeminiTranscriber(apiKey: settings.geminiKey,
                                            model: settings.geminiModel)
        }
    }

    /// Transcribe one chunk, respecting the parallelism cap. Never throws —
    /// returns "" on failure so a single bad chunk can't sink the session.
    func transcribe(_ chunk: AudioChunk) async -> String {
        await semaphore.wait()
        defer { Task { await semaphore.signal() } }
        do {
            // Keep the WAV on disk (1-day retention, cleaned up by Store) so you
            // can replay it and so voiceprint enrollment can reuse it.
            let text = try await transcriber.transcribe(chunk)
            return TranscriptClean.clean(text)
        } catch {
            onError?(error.localizedDescription)
            return ""
        }
    }
}

/// Placeholder until configured.
struct NullTranscriber: Transcriber {
    func transcribe(_ chunk: AudioChunk) async throws -> String { "" }
}
