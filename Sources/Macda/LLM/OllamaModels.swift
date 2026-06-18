import Foundation

/// Fetches the list of models installed on an Ollama server so the user can
/// pick one instead of typing a name (and hitting "model not found").
enum OllamaModels {
    static func list(baseURL: String) async -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = obj["models"] as? [[String: Any]] else { return [] }
            return models.compactMap { $0["name"] as? String }.sorted()
        } catch {
            return []
        }
    }
}
