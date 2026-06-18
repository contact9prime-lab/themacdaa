import Foundation

/// A small tool-using agent that reasons over your *local* data — notes,
/// to-dos, meetings, transcripts — and can take actions on them. It runs a
/// ReAct-style JSON loop against whatever LLM you've configured (Ollama by
/// default), so everything can stay on-device.
@MainActor
final class AgentEngine {
    private weak var appState: AppState?
    private let maxSteps = 6

    init(appState: AppState) { self.appState = appState }

    private var provider: LLMProvider {
        let s = appState?.settings ?? Settings()
        switch s.llmProvider {
        case .ollama: return OllamaProvider(baseURL: s.ollamaBaseURL, model: s.ollamaModel)
        case .openAI: return OpenAIChatProvider(apiKey: s.openAIKey, model: s.openAIModel)
        case .gemini: return GeminiChatProvider(apiKey: s.geminiKey, model: s.geminiModel)
        }
    }

    /// Handle one user turn. Returns the trace (tool steps) + final reply,
    /// streaming each step back via `onStep` so the UI can update live.
    func respond(to userText: String, history: [ChatMessage], onStep: @escaping (ChatMessage) -> Void) async {
        var scratch = ""    // running observations for this turn
        do {
            for step in 0..<maxSteps {
                let prompt = buildPrompt(history: history, userText: userText, scratch: scratch, step: step)
                let raw = try await provider.complete(system: systemPrompt, user: prompt, json: true)
                let decision = AgentDecision.parse(raw)

                if let final = decision.final, !final.isEmpty {
                    onStep(ChatMessage(role: .assistant, text: final))
                    return
                }
                guard let tool = decision.tool else {
                    // Model didn't pick a tool or a final answer — treat raw as answer.
                    onStep(ChatMessage(role: .assistant, text: decision.thought ?? cleaned(raw)))
                    return
                }
                let observation = runTool(tool, args: decision.args)
                onStep(ChatMessage(role: .tool, text: "🔧 \(tool)(\(compact(decision.args))) → \(observation)"))
                scratch += "\nStep \(step + 1): used \(tool)(\(compact(decision.args))) → \(observation)"
            }
            onStep(ChatMessage(role: .assistant,
                               text: "I gathered some info but couldn't wrap it up — could you narrow it down?"))
        } catch {
            onStep(ChatMessage(role: .assistant,
                               text: "⚠️ Couldn't reach the LLM: \(error.localizedDescription)"))
        }
    }

    // MARK: - Tools (operate on local data)

    private func runTool(_ tool: String, args: [String: String]) -> String {
        guard let app = appState else { return "no data" }
        switch tool {
        case "search_notes":
            let q = (args["query"] ?? "").lowercased()
            let hits = app.notes.filter { q.isEmpty || $0.text.lowercased().contains(q) }.prefix(6)
            return hits.isEmpty ? "no matching notes"
                : hits.map { "• \($0.text)" }.joined(separator: "\n")
        case "search_meetings":
            let q = (args["query"] ?? "").lowercased()
            let hits = app.meetings.filter {
                q.isEmpty || $0.title.lowercased().contains(q)
                    || $0.summary.lowercased().contains(q)
                    || $0.transcript.lowercased().contains(q)
            }.prefix(5)
            return hits.isEmpty ? "no matching meetings"
                : hits.map { "• \($0.title) (\($0.startedAt.formatted(date: .abbreviated, time: .shortened))): \($0.summary)" }
                    .joined(separator: "\n")
        case "recent_activity":
            let days = Double(args["days"] ?? "1") ?? 1
            let cutoff = Date().addingTimeInterval(-days * 86_400)
            let ms = app.meetings.filter { $0.startedAt >= cutoff }.prefix(10)
            let ns = app.notes.filter { $0.createdAt >= cutoff }.prefix(15)
            let ts = app.todos.filter { $0.createdAt >= cutoff && !$0.done }.prefix(15)
            if ms.isEmpty && ns.isEmpty && ts.isEmpty {
                return "nothing recorded in the last \(Int(days)) day(s)"
            }
            var out = ""
            if !ms.isEmpty { out += "Meetings:\n" + ms.map { "• \($0.title): \($0.summary)" }.joined(separator: "\n") + "\n" }
            if !ns.isEmpty { out += "Notes:\n" + ns.map { "• \($0.text)" }.joined(separator: "\n") + "\n" }
            if !ts.isEmpty { out += "Open to-dos:\n" + ts.map { "• \($0.title)" }.joined(separator: "\n") }
            return out
        case "list_todos":
            let status = args["status"] ?? "open"
            let items = app.todos.filter {
                switch status { case "done": return $0.done; case "all": return true; default: return !$0.done }
            }.prefix(20)
            return items.isEmpty ? "no to-dos"
                : items.map { "• [\($0.done ? "x" : " ")] \($0.title)" }.joined(separator: "\n")
        case "add_todo":
            guard let title = args["title"], !title.isEmpty else { return "missing title" }
            let due = args["due"].flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) }
            app.todos.insert(TodoItem(title: title, due: due, meetingID: nil, createdAt: Date()), at: 0)
            app.persistChatData()
            return "added to-do: \(title)"
        case "add_note":
            guard let text = args["text"], !text.isEmpty else { return "missing text" }
            app.addManualNote(text)
            return "saved note"
        default:
            return "unknown tool"
        }
    }

    // MARK: - Prompt building

    private var systemPrompt: String {
        """
        You are Macda, a friendly on-device assistant with access to the user's \
        local notes, to-dos, and meeting transcripts. Use tools to look things up \
        or make changes before answering. Think step by step.

        Reply with STRICT JSON only, one object, matching ONE of these shapes:
        • To use a tool:   {"thought": "...", "tool": "<name>", "args": { ... }}
        • To answer:       {"thought": "...", "final": "your reply to the user"}

        Tools:
        • recent_activity{"days": 1}            ← use for "today" / "recent" / "what happened"
        • search_notes   {"query": "keywords"}
        • search_meetings{"query": "keywords"}
        • list_todos     {"status": "open|done|all"}
        • add_todo       {"title": "...", "due": "YYYY-MM-DD or omit"}
        • add_note       {"text": "..."}

        For time-based questions ("today", "this week", "what happened", "recent"), \
        use recent_activity — NEVER search_notes/search_meetings with a date string, \
        that won't match. Use search_* only for topic keywords. Prefer looking data \
        up before claiming you don't know. When you have enough, give a concise, \
        helpful "final" answer. Don't invent notes or meetings.
        """
    }

    private func buildPrompt(history: [ChatMessage], userText: String, scratch: String, step: Int) -> String {
        var p = "Today is \(Date().formatted(date: .complete, time: .omitted)).\n\n"
        if let app = appState { p += dataOverview(app) + "\n\n" }

        let convo = history.suffix(8).filter { $0.role != .tool }
        if !convo.isEmpty {
            p += "Conversation so far:\n"
            for m in convo { p += "\(m.role == .user ? "User" : "Macda"): \(m.text)\n" }
            p += "\n"
        }
        p += "Current user request: \(userText)\n"
        if !scratch.isEmpty { p += "\nWhat you've done this turn:\(scratch)\n" }
        p += "\nDecide the next single step as JSON."
        return p
    }

    private func dataOverview(_ app: AppState) -> String {
        let openTodos = app.todos.filter { !$0.done }.count
        return "Snapshot: \(app.notes.count) notes, \(openTodos) open to-dos, \(app.meetings.count) meetings on file."
    }

    private func compact(_ args: [String: String]) -> String {
        args.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }

    private func cleaned(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Parsed agent decision from the model's JSON.
struct AgentDecision {
    var thought: String?
    var tool: String?
    var args: [String: String]
    var final: String?

    static func parse(_ raw: String) -> AgentDecision {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AgentDecision(thought: nil, tool: nil, args: [:], final: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var args: [String: String] = [:]
        if let raw = obj["args"] as? [String: Any] {
            for (k, v) in raw { args[k] = String(describing: v) }
        }
        return AgentDecision(
            thought: obj["thought"] as? String,
            tool: obj["tool"] as? String,
            args: args,
            final: obj["final"] as? String)
    }
}
