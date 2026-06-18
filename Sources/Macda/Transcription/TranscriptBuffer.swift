import Foundation

/// Accumulates transcript text across a session. Used only on the main actor.
final class TranscriptBuffer {
    private var pieces: [String] = []

    func reset() { pieces.removeAll() }

    func append(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pieces.append(trimmed)
    }

    func fullText() -> String {
        pieces.joined(separator: " ")
    }

    /// The last ~280 characters, for the live preview bubble.
    func recentTail() -> String {
        let full = fullText()
        if full.count <= 280 { return full }
        return "…" + String(full.suffix(280))
    }
}
