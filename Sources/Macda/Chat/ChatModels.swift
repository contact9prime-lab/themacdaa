import Foundation

/// One line in the chat with Macda. `tool` messages are the agent's visible
/// reasoning/actions (dimmed in the UI) so you can see what it did to your data.
struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable { case user, assistant, tool }
    var id = UUID()
    var role: Role
    var text: String
    var createdAt: Date = Date()
}

extension ChatMessage {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOr(.id, UUID())
        role = c.decodeOr(.role, .assistant)
        text = c.decodeOr(.text, "")
        createdAt = c.decodeOr(.createdAt, Date())
    }
}
