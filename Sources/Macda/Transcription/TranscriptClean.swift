import Foundation

/// Strips non-speech artifacts that transcribers emit — whisper.cpp in
/// particular tags silence/sounds like "[BLANK_AUDIO]", "[ Silence ]",
/// "[MUSIC]" — so they don't pollute the transcript or the LLM's notes.
enum TranscriptClean {
    static func clean(_ text: String) -> String {
        var t = text
        let patterns = [
            #"\[[^\]]*\]"#,   // [BLANK_AUDIO], [ Silence ], [MUSIC], [ Inaudible ]
            #"(?i)\((?:blank[ _]?audio|silence|music|inaudible|applause|laughter|noise|coughs?|sighs?)\)"#,
            #"[♪♫🎵🎶]"#       // music notes
        ]
        for p in patterns {
            t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
