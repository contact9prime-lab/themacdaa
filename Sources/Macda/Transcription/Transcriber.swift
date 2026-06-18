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
    private var fallback: Transcriber?      // whisper.cpp safety net for flaky LLM transcription
    private var semaphore = AsyncSemaphore(value: 3)

    /// Reports the reason a chunk failed to transcribe (model not found, etc.).
    var onError: ((String) -> Void)?

    func configure(with settings: Settings) {
        semaphore = AsyncSemaphore(value: settings.parallelTranscriptions)
        // If the primary isn't local whisper but whisper is ready, use it as a
        // fallback when the primary yields nothing usable.
        fallback = (settings.transcriptionProvider != .whisperCpp && settings.whisperReady)
            ? WhisperCppTranscriber(binary: settings.whisperCppBinaryPath, model: settings.whisperModelPath,
                                    language: settings.whisperLanguage)
            : nil
        switch settings.transcriptionProvider {
        case .ollamaAudio:
            let model = settings.ollamaTranscribeModel.isEmpty ? settings.ollamaModel : settings.ollamaTranscribeModel
            transcriber = OllamaAudioTranscriber(baseURL: settings.ollamaBaseURL, model: model)
        case .whisperCpp:
            transcriber = WhisperCppTranscriber(binary: settings.whisperCppBinaryPath,
                                                model: settings.whisperModelPath,
                                                language: settings.whisperLanguage)
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
            // Keep the WAV on disk (1-day retention) so you can replay it and so
            // voiceprint enrollment can reuse it.
            let text = TranscriptClean.clean(try await transcriber.transcribe(chunk))
            // LLM transcribers sometimes refuse/editorialize → empty after cleaning.
            // Fall back to local whisper so a session is never silently lost.
            if text.isEmpty, let fallback {
                return TranscriptClean.clean((try? await fallback.transcribe(chunk)) ?? "")
            }
            return text
        } catch {
            onError?(error.localizedDescription)
            if let fallback {
                return TranscriptClean.clean((try? await fallback.transcribe(chunk)) ?? "")
            }
            return ""
        }
    }

    /// Quick, best-effort transcription for the live bubble — bypasses the main
    /// concurrency cap so it stays snappy, and never reports errors.
    func transcribePreview(_ chunk: AudioChunk) async -> String {
        let cleaned = TranscriptClean.clean((try? await transcriber.transcribe(chunk)) ?? "")
        if cleaned.isEmpty, let fallback {
            return TranscriptClean.clean((try? await fallback.transcribe(chunk)) ?? "")
        }
        return cleaned
    }
}

/// Placeholder until configured.
struct NullTranscriber: Transcriber {
    func transcribe(_ chunk: AudioChunk) async throws -> String { "" }
}
