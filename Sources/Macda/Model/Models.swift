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
    var audioFiles: [String] = []   // chunk WAV paths (retained per the storage limit)

    var durationString: String {
        guard let endedAt else { return "in progress" }
        let secs = Int(endedAt.timeIntervalSince(startedAt))
        return "\(secs / 60)m \(secs % 60)s"
    }
}

struct NoteItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var tags: [String] = []
    var meetingID: UUID?
    var createdAt: Date
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var assignee: String = ""      // owner of the task (defaults to you)
    var due: Date?
    var done: Bool = false
    var reminded: Bool = false     // we've already popped a reminder for this
    var meetingID: UUID?
    var createdAt: Date
}

// MARK: - Tolerant decoding
// A missing key falls back to a default instead of throwing — so adding a field
// to any model NEVER wipes existing saved data. (Lesson learned the hard way.)

extension KeyedDecodingContainer {
    func decodeOr<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    func decodeOpt<T: Decodable>(_ key: Key, _ type: T.Type) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}

extension Meeting {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOr(.id, UUID()); title = c.decodeOr(.title, "")
        attendees = c.decodeOr(.attendees, []); tags = c.decodeOr(.tags, [])
        startedAt = c.decodeOr(.startedAt, Date()); endedAt = c.decodeOpt(.endedAt, Date.self)
        summary = c.decodeOr(.summary, ""); transcript = c.decodeOr(.transcript, "")
        speakers = c.decodeOr(.speakers, []); audioFiles = c.decodeOr(.audioFiles, [])
    }
}
extension NoteItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOr(.id, UUID()); text = c.decodeOr(.text, ""); tags = c.decodeOr(.tags, [])
        meetingID = c.decodeOpt(.meetingID, UUID.self); createdAt = c.decodeOr(.createdAt, Date())
    }
}
extension TodoItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOr(.id, UUID()); title = c.decodeOr(.title, ""); assignee = c.decodeOr(.assignee, "")
        due = c.decodeOpt(.due, Date.self); done = c.decodeOr(.done, false); reminded = c.decodeOr(.reminded, false)
        meetingID = c.decodeOpt(.meetingID, UUID.self); createdAt = c.decodeOr(.createdAt, Date())
    }
}
extension Person {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOr(.id, UUID()); name = c.decodeOr(.name, ""); role = c.decodeOr(.role, "")
        aliases = c.decodeOr(.aliases, []); voiceNote = c.decodeOr(.voiceNote, "")
        voicePrint = c.decodeOr(.voicePrint, []); voiceSamplePath = c.decodeOr(.voiceSamplePath, "")
        createdAt = c.decodeOr(.createdAt, Date())
    }
}
extension DetectedSpeaker {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOr(.id, UUID()); label = c.decodeOr(.label, ""); sampleQuote = c.decodeOr(.sampleQuote, "")
        personID = c.decodeOpt(.personID, UUID.self); embedding = c.decodeOr(.embedding, [])
        sampleAudioPath = c.decodeOr(.sampleAudioPath, "")
    }
}
extension PendingVoice {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOr(.id, UUID()); label = c.decodeOr(.label, ""); sampleQuote = c.decodeOr(.sampleQuote, "")
        embedding = c.decodeOr(.embedding, []); sampleAudioPath = c.decodeOr(.sampleAudioPath, "")
        meetingID = c.decodeOpt(.meetingID, UUID.self); meetingTitle = c.decodeOr(.meetingTitle, "")
        createdAt = c.decodeOr(.createdAt, Date())
    }
}
extension Artifact {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeOr(.id, UUID()); imagePath = c.decodeOr(.imagePath, ""); aiText = c.decodeOr(.aiText, "")
        meetingID = c.decodeOpt(.meetingID, UUID.self); createdAt = c.decodeOr(.createdAt, Date())
        analyzing = c.decodeOr(.analyzing, false)
    }
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

/// A transcript whose note-extraction failed (LLM down) — retried periodically.
struct PendingExtraction: Codable, Identifiable {
    var id = UUID()
    var meetingID: UUID
    var transcript: String
    var createdAt: Date = Date()
    var attempts: Int = 0
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
    struct Todo: Codable { var title: String; var due: Date?; var owner: String? }
    struct Note: Codable { var text: String; var tags: [String] = [] }
    var summary: String
    var notes: [Note]
    var todos: [Todo]
    var speakers: [DetectedSpeaker] = []
}
