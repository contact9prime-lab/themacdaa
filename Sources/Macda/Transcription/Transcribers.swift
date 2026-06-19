import Foundation

// MARK: - Local: whisper.cpp

/// Shells out to a whisper.cpp binary (e.g. `whisper-cli`). Fully local & private.
/// Install:  brew install whisper-cpp   (or build from ggerganov/whisper.cpp)
/// Model:    download ggml-base.en.bin and point Settings at it.
struct WhisperCppTranscriber: Transcriber {
    /// Set once a Metal/GPU init failure is seen, so we stop trying the GPU.
    nonisolated(unsafe) static var gpuDisabled = false

    let binary: String
    let model: String
    var language: String = "auto"
    var useGPU: Bool = true

    func transcribe(_ chunk: AudioChunk) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw TranscriberError.missingConfig("whisper.cpp binary not found at \(binary). Set it in Settings.")
        }
        guard !model.isEmpty, FileManager.default.fileExists(atPath: model) else {
            throw TranscriberError.missingConfig("whisper model not set. Point Settings at a ggml-*.bin file.")
        }
        let lang = language.isEmpty ? "auto" : language
        let noGPU = !useGPU || Self.gpuDisabled
        do {
            return Self.parse(try run(file: chunk.url.path, lang: lang, noGPU: noGPU))
        } catch {
            // Some ggml builds crash initializing the Metal backend — retry on CPU.
            let m = error.localizedDescription.lowercased()
            let gpuError = m.contains("metal") || m.contains("ggml") || m.contains("whisper context") || m.contains("assert")
            if !noGPU && gpuError {
                Self.gpuDisabled = true
                Log.error("whisper GPU/Metal init failed — switching to CPU (-ng) for this session.")
                return Self.parse(try run(file: chunk.url.path, lang: lang, noGPU: true))
            }
            throw error
        }
    }

    private func run(file: String, lang: String, noGPU: Bool) throws -> String {
        var args = ["-m", model, "-f", file, "-nt", "-np", "-l", lang]
        if noGPU { args.append("-ng") }
        return try Process.run(executable: binary, arguments: args)
    }

    private static func parse(_ output: String) -> String {
        output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Ollama multimodal audio (local LLM)

/// Sends the 16kHz-mono WAV chunk to an audio-capable Ollama model (gemma4,
/// gemma3n, minicpm-o) via the /api/chat `images` array. Fully local-to-you,
/// no cloud key. `think:false` keeps the output to just the transcript.
struct OllamaAudioTranscriber: Transcriber {
    let baseURL: String
    let model: String

    func transcribe(_ chunk: AudioChunk) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw TranscriberError.missingConfig("Bad Ollama URL.")
        }
        let audio = try Data(contentsOf: chunk.url).base64EncodedString()
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "think": false,
            "keep_alive": "30m",
            "options": ["temperature": 0],
            "messages": [
                ["role": "system", "content": """
                You are a speech-to-text transcription engine. Transcribe the audio \
                and output ONLY the exact words spoken, verbatim, in the original \
                language. Output nothing except those words: no labels (e.g. \
                "transcribed_text:", "transcript:"), no quotes, no markdown, no \
                translation, no summary, no commentary, no explanation. If there is \
                no clear speech, output an empty string.
                """],
                ["role": "user", "content": "Transcribe this audio. Output only the spoken words.", "images": [audio]]
            ]
        ]
        let data = try await Networking.postJSON(url, payload)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranscriberError.decode("Unexpected Ollama response.")
        }
        // Guard against the model "helping" with an analysis instead of a transcript.
        if Self.looksLikeAnalysis(content) { return "" }
        return Self.stripLabels(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Remove stray leading labels some models add, e.g. "transcribed_text: …".
    static func stripLabels(_ s: String) -> String {
        var out = s
        let labels = ["transcribed_text:", "transcript:", "transcription:", "text:", "output:"]
        for label in labels where out.lowercased().hasPrefix(label) {
            out = String(out.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// Heuristic: a real transcript isn't markdown, an analysis, or a chatbot
    /// reply like "I'm not sure" / "please provide the audio file".
    static func looksLikeAnalysis(_ s: String) -> Bool {
        let markers = ["###", "**", "➡", "→ \"", "breakdown", "in a professional context",
                       "you could say", "please provide", "i'm not sure", "i am not sure",
                       "as an ai", "i cannot", "i can't transcribe", "the audio file",
                       "could you please", "no audio"]
        let lower = s.lowercased()
        return markers.contains { lower.contains($0) }
    }
}

// MARK: - OpenRouter (free audio models, OpenAI-compatible)

/// Transcribes by sending the WAV to an audio-capable model on OpenRouter via
/// the OpenAI-compatible chat API (`input_audio` content). Many models are free.
struct OpenRouterTranscriber: Transcriber {
    let apiKey: String
    let model: String

    func transcribe(_ chunk: AudioChunk) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriberError.missingConfig("OpenRouter API key missing.") }
        let audio = try Data(contentsOf: chunk.url).base64EncodedString()
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        let payload: [String: Any] = [
            "model": model,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": "Transcribe the speech in this audio verbatim, in its original language. Output only the spoken words — no commentary, labels, or translation."],
                    ["type": "input_audio", "input_audio": ["data": audio, "format": "wav"]]
                ]
            ]]
        ]
        let data = try await Networking.postJSON(url, payload, headers: OpenRouter.headers(apiKey))
        return OpenRouter.content(from: data)
    }
}

/// Shared OpenRouter helpers.
enum OpenRouter {
    static func headers(_ apiKey: String) -> [String: String] {
        ["Authorization": "Bearer \(apiKey)",
         "HTTP-Referer": "https://github.com/contact9prime-lab/themacdaa",
         "X-Title": "Macda"]
    }
    static func content(from data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return "" }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - OpenAI Whisper

struct OpenAITranscriber: Transcriber {
    let apiKey: String
    let model: String

    func transcribe(_ chunk: AudioChunk) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriberError.missingConfig("OpenAI API key missing.") }
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let audio = try Data(contentsOf: chunk.url)
        let body = MultipartBuilder()
        body.addField("model", value: model)
        body.addFile("file", filename: "audio.wav", mimeType: "audio/wav", data: audio)
        req.setValue("multipart/form-data; boundary=\(body.boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.finalize()

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Networking.ensureOK(resp, data)
        struct R: Decodable { let text: String }
        return (try? JSONDecoder().decode(R.self, from: data).text) ?? ""
    }
}

// MARK: - Gemini

struct GeminiTranscriber: Transcriber {
    let apiKey: String
    let model: String

    func transcribe(_ chunk: AudioChunk) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriberError.missingConfig("Gemini API key missing.") }
        let audio = try Data(contentsOf: chunk.url).base64EncodedString()
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": "Transcribe this audio verbatim. Return only the spoken words."],
                    ["inline_data": ["mime_type": "audio/wav", "data": audio]]
                ]
            ]]
        ]
        let data = try await Networking.postJSON(url, payload)
        return GeminiResponse.text(from: data)
    }
}
