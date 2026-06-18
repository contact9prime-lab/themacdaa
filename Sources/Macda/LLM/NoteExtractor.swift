import Foundation

/// Turns a raw transcript into a summary, notes, and to-dos using the user's LLM.
struct NoteExtractor {
    let settings: Settings

    private var provider: LLMProvider {
        switch settings.llmProvider {
        case .ollama: return OllamaProvider(baseURL: settings.ollamaBaseURL, model: settings.ollamaModel)
        case .openAI: return OpenAIChatProvider(apiKey: settings.openAIKey, model: settings.openAIModel)
        case .gemini: return GeminiChatProvider(apiKey: settings.geminiKey, model: settings.geminiModel)
        }
    }

    /// `knownPeople` lets the model attribute speech to people you've tagged.
    func extract(transcript: String, meeting: Meeting?, knownPeople: [Person] = []) async throws -> ExtractionResult {
        let context = meeting.map { m in
            "Meeting: \(m.title)\nAttendees: \(m.attendees.joined(separator: ", "))\nTags: \(m.tags.joined(separator: ", "))"
        } ?? "Meeting: (untitled call)"

        let peopleLine: String = {
            guard !knownPeople.isEmpty else { return "Known people: (none tagged yet)" }
            let names = knownPeople.map { p in
                let aka = p.aliases.isEmpty ? "" : " (aka \(p.aliases.joined(separator: ", ")))"
                return "\(p.name)\(aka)"
            }
            return "Known people you can attribute speech to: \(names.joined(separator: "; "))"
        }()

        let system = """
        You are Macda, a concise meeting assistant. Read a call transcript and \
        extract structured output. Reply with STRICT JSON only, no prose, matching:
        {
          "summary": "2-3 sentence summary",
          "notes": ["short bullet note", ...],
          "todos": [{"title": "actionable task", "due": "YYYY-MM-DD or null"}, ...],
          "speakers": [{"label": "name if known else Speaker 1/2/…", "sampleQuote": "a short line they said"}]
        }
        Notes must be COMPLETE, not a short summary: capture every substantive \
        point, decision, number, name, and detail discussed. Group related points \
        about the SAME topic into ONE coherent multi-sentence note rather than \
        fragmenting them — each note should read as a self-contained mini-story. \
        Do not drop details to be brief. Todos are concrete action items with an \
        owner if mentioned; infer due dates from phrases like "by Friday" relative \
        to today, otherwise null. For speakers, list each DISTINCT voice; if a \
        known person clearly matches, use their name, else "Speaker 1", "Speaker 2".
        """

        let today = ISO8601DateFormatter.dateOnly.string(from: Date())
        let user = """
        Today is \(today).
        \(context)
        \(peopleLine)

        TRANSCRIPT:
        \(transcript)
        """

        let raw = try await provider.complete(system: system, user: user, json: true)
        return Self.parse(raw)
    }

    /// Lenient parse — models sometimes wrap JSON in fences or stray text.
    static func parse(_ raw: String) -> ExtractionResult {
        let json = extractJSONObject(from: raw)
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ExtractionResult(summary: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                                    notes: [], todos: [])
        }
        let summary = obj["summary"] as? String ?? ""
        let notes = (obj["notes"] as? [Any])?.compactMap { $0 as? String } ?? []
        let todos: [ExtractionResult.Todo] = (obj["todos"] as? [[String: Any]])?.compactMap { t in
            guard let title = t["title"] as? String, !title.isEmpty else { return nil }
            let due = (t["due"] as? String).flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) }
            return ExtractionResult.Todo(title: title, due: due)
        } ?? []
        let speakers: [DetectedSpeaker] = (obj["speakers"] as? [[String: Any]])?.compactMap { s in
            guard let label = s["label"] as? String, !label.isEmpty else { return nil }
            return DetectedSpeaker(label: label, sampleQuote: s["sampleQuote"] as? String ?? "")
        } ?? []
        return ExtractionResult(summary: summary, notes: notes, todos: todos, speakers: speakers)
    }

    private static func extractJSONObject(from raw: String) -> String {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else {
            return raw
        }
        return String(raw[start...end])
    }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
