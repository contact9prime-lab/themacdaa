import Foundation

/// Sends a screenshot to a multimodal model and returns an artifact description.
/// Mirrors the transcription/LLM provider choice; defaults to local Ollama
/// (gemma4 understands images) with a selectable model.
struct VisionAnalyzer {
    let settings: Settings

    private var model: String {
        settings.visionModel.isEmpty ? settings.ollamaModel : settings.visionModel
    }

    private let prompt = """
    You are looking at a screenshot from a screen-shared meeting. In 2-4 sentences, \
    describe what's on screen (app, slide, document, chart…). Then, if present, list \
    key text, numbers, decisions, or action items visible. Be concise and factual; \
    don't invent anything.
    """

    func analyze(pngData: Data) async throws -> String {
        let b64 = pngData.base64EncodedString()
        switch settings.llmProvider {
        case .ollama:
            return try await ollama(b64)
        case .openAI:
            return try await openAI(b64)
        case .gemini:
            return try await gemini(b64)
        }
    }

    private func ollama(_ b64: String) async throws -> String {
        guard let url = URL(string: "\(settings.ollamaBaseURL)/api/chat") else {
            throw TranscriberError.missingConfig("Bad Ollama URL.")
        }
        let payload: [String: Any] = [
            "model": model, "stream": false, "think": false, "keep_alive": "30m",
            "messages": [["role": "user", "content": prompt, "images": [b64]]]
        ]
        let data = try await Networking.postJSON(url, payload)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranscriberError.decode("Unexpected Ollama vision response.")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openAI(_ b64: String) async throws -> String {
        guard !settings.openAIKey.isEmpty else { throw TranscriberError.missingConfig("OpenAI API key missing.") }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let payload: [String: Any] = [
            "model": settings.visionModel.isEmpty ? "gpt-4o-mini" : settings.visionModel,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(b64)"]]
                ]
            ]]
        ]
        let data = try await Networking.postJSON(url, payload, headers: ["Authorization": "Bearer \(settings.openAIKey)"])
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranscriberError.decode("Unexpected OpenAI vision response.")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func gemini(_ b64: String) async throws -> String {
        guard !settings.geminiKey.isEmpty else { throw TranscriberError.missingConfig("Gemini API key missing.") }
        let m = settings.visionModel.isEmpty ? settings.geminiModel : settings.visionModel
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(m):generateContent?key=\(settings.geminiKey)")!
        let payload: [String: Any] = [
            "contents": [["parts": [
                ["text": prompt],
                ["inline_data": ["mime_type": "image/png", "data": b64]]
            ]]]
        ]
        let data = try await Networking.postJSON(url, payload)
        return GeminiResponse.text(from: data)
    }
}
