import Foundation

struct Meeting: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var attendees: [String] = []
    var tags: [String] = []
    var startedAt: Date
    var endedAt: Date?
    var summary: String = ""
    var transcript: String = ""
    var speakers: [DetectedSpeaker] = []

    var durationString: String {
        guard let endedAt else { return "in progress" }
        let secs = Int(endedAt.timeIntervalSince(startedAt))
        return "\(secs / 60)m \(secs % 60)s"
    }
}

struct NoteItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var meetingID: UUID?
    var createdAt: Date
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var due: Date?
    var done: Bool = false
    var meetingID: UUID?
    var createdAt: Date
}

/// One transcription unit handed to a provider.
struct AudioChunk: Sendable {
    let url: URL          // 16kHz mono PCM16 WAV on disk
    let index: Int        // ordering within the session
    let duration: Double
    var embedding: [Float] = []   // voiceprint of this chunk's audio
}

/// A person Macda knows about — used to attribute who said what.
struct Person: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var role: String = ""          // e.g. "PM at Acme"
    var aliases: [String] = []     // other names the LLM might use for them
    var voiceNote: String = ""     // your description of their voice/footprint
    var voicePrint: [Float] = []   // acoustic embedding for auto-recognition
    var voiceSamplePath: String = ""  // a retained audio clip of them, for replay
    var createdAt: Date = Date()

    var hasVoiceprint: Bool { !voicePrint.isEmpty }
}

/// A distinct speaker, identified acoustically (voiceprint) or by the LLM.
struct DetectedSpeaker: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String              // "Speaker 1" or a known person's name
    var sampleQuote: String = ""
    var personID: UUID?            // set when matched/tagged to a Person
    var embedding: [Float] = []    // this speaker's voiceprint for enrollment
    var sampleAudioPath: String = ""  // a chunk of this speaker's audio, to play back
}

/// An untagged voice surfaced after a call: "new voice found — who is this?"
struct PendingVoice: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var sampleQuote: String
    var embedding: [Float] = []    // enroll this as the person's voiceprint on tag
    var sampleAudioPath: String = ""  // audio clip of this voice, to listen before tagging
    var meetingID: UUID?
    var meetingTitle: String
    var createdAt: Date = Date()
}

/// A captured screen snapshot plus its AI analysis, attached to a meeting.
struct Artifact: Identifiable, Codable, Hashable {
    var id = UUID()
    var imagePath: String
    var aiText: String = ""
    var meetingID: UUID?
    var createdAt: Date = Date()
    var analyzing: Bool = false
}

/// Result of asking the LLM to turn a transcript into structured output.
struct ExtractionResult: Codable {
    struct Todo: Codable { var title: String; var due: Date? }
    var summary: String
    var notes: [String]
    var todos: [Todo]
    var speakers: [DetectedSpeaker] = []
}
