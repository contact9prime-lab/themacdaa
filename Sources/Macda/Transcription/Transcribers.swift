import Foundation

// MARK: - Local: whisper.cpp

/// Shells out to a whisper.cpp binary (e.g. `whisper-cli`). Fully local & private.
/// Install:  brew install whisper-cpp   (or build from ggerganov/whisper.cpp)
/// Model:    download ggml-base.en.bin and point Settings at it.
struct WhisperCppTranscriber: Transcriber {
    let binary: String
    let model: String

    func transcribe(_ chunk: AudioChunk) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw TranscriberError.missingConfig("whisper.cpp binary not found at \(binary). Set it in Settings.")
        }
        guard !model.isEmpty, FileManager.default.fileExists(atPath: model) else {
            throw TranscriberError.missingConfig("whisper model not set. Point Settings at a ggml-*.bin file.")
        }
        let args = ["-m", model, "-f", chunk.url.path, "-nt", "-np", "-l", "auto"]
        let output = try Process.run(executable: binary, arguments: args)
        // whisper.cpp prints the transcript to stdout (no timestamps with -nt).
        return output
            .split(separator: "\n")
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
                You are an automatic speech recognition (ASR) engine, not a chatbot. \
                Your ONLY output is the exact words spoken in the user's audio, \
                transcribed verbatim. Never translate, rephrase, summarize, correct, \
                analyze, or explain. Never use markdown, headings, bullet points, or \
                quotation marks. If there is no intelligible speech, output an empty \
                string.
                """],
                ["role": "user", "content": "Transcribe this audio.", "images": [audio]]
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
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
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
