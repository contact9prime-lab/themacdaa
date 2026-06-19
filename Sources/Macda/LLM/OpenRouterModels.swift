import Foundation

/// Fetches the OpenRouter catalog so the UI can show FREE models, flagging which
/// ones accept audio (for transcription) vs text-only (for notes/chat).
enum OpenRouterModels {
    struct Model: Identifiable, Hashable {
        let id: String
        let name: String
        let free: Bool
        let audio: Bool
    }

    static func list() async -> [Model] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return [] }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = obj["data"] as? [[String: Any]] else { return [] }
            return arr.compactMap { m -> Model? in
                guard let id = m["id"] as? String else { return nil }
                let name = m["name"] as? String ?? id
                let pricing = m["pricing"] as? [String: Any]
                let prompt = Double((pricing?["prompt"] as? String) ?? "1") ?? 1
                let completion = Double((pricing?["completion"] as? String) ?? "1") ?? 1
                let free = prompt == 0 && completion == 0
                let inputs = (m["architecture"] as? [String: Any])?["input_modalities"] as? [String] ?? []
                return Model(id: id, name: name, free: free, audio: inputs.contains("audio"))
            }
            .sorted { $0.name < $1.name }
        } catch {
            return []
        }
    }
}
