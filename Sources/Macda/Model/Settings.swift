import Foundation

enum TranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case whisperCpp   // local, via whisper.cpp binary — accurate, fast
    case openAI       // Whisper API
    case gemini       // Gemini audio understanding
    case ollamaAudio  // local multimodal LLM (gemma4 / gemma3n) — experimental
    var id: String { rawValue }
    var label: String {
        switch self {
        case .whisperCpp: return "whisper.cpp (local, recommended)"
        case .openAI: return "OpenAI Whisper"
        case .gemini: return "Gemini"
        case .ollamaAudio: return "Ollama audio LLM (experimental)"
        }
    }
}

enum LLMProviderKind: String, Codable, CaseIterable, Identifiable {
    case ollama   // local
    case openAI
    case gemini
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ollama: return "Ollama (local)"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }
}

struct AudioSourceOptions: OptionSet, Codable {
    let rawValue: Int
    static let microphone = AudioSourceOptions(rawValue: 1 << 0)
    static let system     = AudioSourceOptions(rawValue: 1 << 1)
    static let both: AudioSourceOptions = [.microphone, .system]
}

struct Settings: Codable {
    // Providers
    var transcriptionProvider: TranscriptionProvider = .whisperCpp
    var llmProvider: LLMProviderKind = .ollama

    // Local tooling
    var whisperCppBinaryPath: String = "/usr/local/bin/whisper-cli"
    var whisperModelPath: String = ""    // e.g. ~/models/ggml-base.en.bin
    var ollamaBaseURL: String = "http://127.0.0.1:11434"
    var ollamaModel: String = "llama3.1"
    var ollamaTranscribeModel: String = ""   // empty = use ollamaModel

    // Cloud keys (stored in UserDefaults for simplicity; move to Keychain for prod)
    var openAIKey: String = ""
    var openAIModel: String = "gpt-4o-mini"
    var openAITranscribeModel: String = "whisper-1"
    var geminiKey: String = ""
    var geminiModel: String = "gemini-1.5-flash"

    // Capture behaviour
    var captureMic = true
    var captureSystem = true
    var micDeviceUID = ""          // empty = system default input
    var autoStopOnSilence = true
    var silenceThreshold: Float = 0.012   // RMS below this counts as "quiet"
    var silenceTimeout: Double = 12        // seconds of quiet before auto-stop
    var maxChunkSeconds: Double = 20       // hard cut for batching
    var parallelTranscriptions = 3         // batch concurrency
    var customDataDirectory = ""           // empty = default Application Support
    var recordingRetentionDays = 1         // keep audio chunks this many days
    var maxStorageMB = 500                 // prune oldest recordings past this size

    // Mascot appearance
    var mascotScale: Double = 0.62         // 0.4 (tiny) … 1.2 (big)
    var mascotColorHex = ""                // empty = default blue
    var showMascot = true

    // Auto-listen
    var autoListen = false                 // start recording automatically on speech

    // Voiceprints
    var voiceMatchThreshold: Float = 0.82  // cosine similarity to call it the same voice

    var audioSources: AudioSourceOptions {
        var s: AudioSourceOptions = []
        if captureMic { s.insert(.microphone) }
        if captureSystem { s.insert(.system) }
        return s.isEmpty ? .microphone : s
    }

    var whisperReady: Bool {
        FileManager.default.isExecutableFile(atPath: whisperCppBinaryPath)
            && !whisperModelPath.isEmpty
    }

    // MARK: Persistence
    private static let key = "macda.settings.v1"

    /// Fixed on-disk location (independent of the custom data dir to avoid a
    /// chicken-and-egg). This is the source of truth; UserDefaults is a mirror.
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Macda", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("settings.json")
    }

    static func load() -> Settings {
        let decoder = JSONDecoder()
        // Prefer the on-disk file; fall back to UserDefaults (older installs).
        if let data = try? Data(contentsOf: fileURL),
           let s = try? decoder.decode(Settings.self, from: data) { return s }
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? decoder.decode(Settings.self, from: data) { return s }
        return Settings()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)   // visible file on disk
        UserDefaults.standard.set(data, forKey: Self.key)      // mirror
    }
}

// Tolerant decoding: a missing key (e.g. a setting added in a newer build)
// falls back to its default instead of throwing — so updates never wipe your
// saved settings. Placed in an extension to keep the memberwise init.
extension Settings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func s<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        self.init()
        transcriptionProvider   = s(.transcriptionProvider, d.transcriptionProvider)
        llmProvider             = s(.llmProvider, d.llmProvider)
        whisperCppBinaryPath    = s(.whisperCppBinaryPath, d.whisperCppBinaryPath)
        whisperModelPath        = s(.whisperModelPath, d.whisperModelPath)
        ollamaBaseURL           = s(.ollamaBaseURL, d.ollamaBaseURL)
        ollamaModel             = s(.ollamaModel, d.ollamaModel)
        ollamaTranscribeModel   = s(.ollamaTranscribeModel, d.ollamaTranscribeModel)
        openAIKey               = s(.openAIKey, d.openAIKey)
        openAIModel             = s(.openAIModel, d.openAIModel)
        openAITranscribeModel   = s(.openAITranscribeModel, d.openAITranscribeModel)
        geminiKey               = s(.geminiKey, d.geminiKey)
        geminiModel             = s(.geminiModel, d.geminiModel)
        captureMic              = s(.captureMic, d.captureMic)
        captureSystem           = s(.captureSystem, d.captureSystem)
        micDeviceUID            = s(.micDeviceUID, d.micDeviceUID)
        autoStopOnSilence       = s(.autoStopOnSilence, d.autoStopOnSilence)
        silenceThreshold        = s(.silenceThreshold, d.silenceThreshold)
        silenceTimeout          = s(.silenceTimeout, d.silenceTimeout)
        maxChunkSeconds         = s(.maxChunkSeconds, d.maxChunkSeconds)
        parallelTranscriptions  = s(.parallelTranscriptions, d.parallelTranscriptions)
        customDataDirectory     = s(.customDataDirectory, d.customDataDirectory)
        recordingRetentionDays  = s(.recordingRetentionDays, d.recordingRetentionDays)
        mascotScale             = s(.mascotScale, d.mascotScale)
        mascotColorHex          = s(.mascotColorHex, d.mascotColorHex)
        showMascot              = s(.showMascot, d.showMascot)
        autoListen              = s(.autoListen, d.autoListen)
        voiceMatchThreshold     = s(.voiceMatchThreshold, d.voiceMatchThreshold)
        maxStorageMB            = s(.maxStorageMB, d.maxStorageMB)
    }
}
