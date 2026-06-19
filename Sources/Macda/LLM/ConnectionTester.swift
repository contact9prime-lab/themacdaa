import Foundation

/// Result of a "can I actually reach this provider?" check, surfaced in Settings.
enum ConnectionStatus: Equatable {
    case idle
    case testing
    case ok(String)      // green — reachable and ready
    case warn(String)    // orange — reachable but something's off (e.g. model missing)
    case fail(String)    // red — couldn't reach it

    var isTesting: Bool { self == .testing }
}

/// Validates the configured LLM backend without running a whole meeting through it.
/// For Ollama (often on another machine) it checks reachability *and* that the
/// chosen model is actually installed there.
struct ConnectionTester {
    let settings: Settings

    func testLLM() async -> ConnectionStatus {
        switch settings.llmProvider {
        case .ollama:
            return await testOllama()
        case .openRouter:
            return await testChat(OpenRouterChatProvider(apiKey: settings.openRouterKey, model: settings.openRouterModel),
                                  label: "OpenRouter")
        case .openAI:
            return await testChat(OpenAIChatProvider(apiKey: settings.openAIKey, model: settings.openAIModel),
                                  label: "OpenAI")
        case .gemini:
            return await testChat(GeminiChatProvider(apiKey: settings.geminiKey, model: settings.geminiModel),
                                  label: "Gemini")
        }
    }

    // MARK: Ollama

    private func testOllama() async -> ConnectionStatus {
        let base = settings.ollamaBaseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(base)/api/tags") else {
            return .fail("Invalid Ollama URL: \(base)")
        }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return .fail("No HTTP response from \(base).")
            }
            guard (200..<300).contains(http.statusCode) else {
                return .fail("\(base) responded HTTP \(http.statusCode).")
            }
            let models = Self.parseOllamaModels(data)
            let target = settings.ollamaModel.trimmingCharacters(in: .whitespaces)
            if models.isEmpty {
                return .warn("Reached \(base), but no models are installed there. Run `ollama pull \(target)` on that machine.")
            }
            let installed = models.contains { name in
                name == target || name.hasPrefix(target + ":") ||
                String(name.split(separator: ":").first ?? "") == target
            }
            if installed {
                return .ok("Connected to \(base) ✓  '\(target)' is available (\(models.count) model\(models.count == 1 ? "" : "s")).")
            }
            return .warn("Connected to \(base), but '\(target)' isn't there. Available: \(models.prefix(6).joined(separator: ", "))")
        } catch {
            return .fail("Couldn't reach \(base): \(error.localizedDescription)")
        }
    }

    private static func parseOllamaModels(_ data: Data) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    // MARK: Cloud chat providers

    private func testChat(_ provider: LLMProvider, label: String) async -> ConnectionStatus {
        do {
            let reply = try await provider.complete(
                system: "You are a connectivity check. Reply with a single word.",
                user: "Reply with the word: ok",
                json: false)
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .warn("\(label) responded, but with empty text. Check the model name.")
            }
            return .ok("\(label) reachable ✓  (replied “\(trimmed.prefix(40))”)")
        } catch {
            return .fail("\(label) failed: \(error.localizedDescription)")
        }
    }
}
