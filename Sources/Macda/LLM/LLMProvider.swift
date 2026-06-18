import Foundation

/// A chat-style LLM that returns a single text completion. Implementations are
/// expected to honour a request for JSON output when `json` is true.
protocol LLMProvider: Sendable {
    func complete(system: String, user: String, json: Bool) async throws -> String
}

// MARK: - Ollama (local, default)

struct OllamaProvider: LLMProvider {
    let baseURL: String
    let model: String

    func complete(system: String, user: String, json: Bool) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw TranscriberError.missingConfig("Bad Ollama URL.")
        }
        var payload: [String: Any] = [
            "model": model,
            "stream": false,
            "think": false,        // no "thinking mode" — clean, fast output
            "keep_alive": "30m",   // keep the model warm to avoid cold-start timeouts
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        if json { payload["format"] = "json" }
        let data = try await Networking.postJSON(url, payload)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranscriberError.decode("Unexpected Ollama response.")
        }
        return content
    }
}

// MARK: - OpenAI

struct OpenAIChatProvider: LLMProvider {
    let apiKey: String
    let model: String

    func complete(system: String, user: String, json: Bool) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriberError.missingConfig("OpenAI API key missing.") }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        if json { payload["response_format"] = ["type": "json_object"] }
        let data = try await Networking.postJSON(url, payload,
                                                 headers: ["Authorization": "Bearer \(apiKey)"])
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranscriberError.decode("Unexpected OpenAI response.")
        }
        return content
    }
}

// MARK: - Gemini

struct GeminiChatProvider: LLMProvider {
    let apiKey: String
    let model: String

    func complete(system: String, user: String, json: Bool) async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriberError.missingConfig("Gemini API key missing.") }
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var generationConfig: [String: Any] = [:]
        if json { generationConfig["responseMimeType"] = "application/json" }
        let payload: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["parts": [["text": user]]]],
            "generationConfig": generationConfig
        ]
        let data = try await Networking.postJSON(url, payload)
        return GeminiResponse.text(from: data)
    }
}
