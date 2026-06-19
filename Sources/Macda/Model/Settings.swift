import Foundation

enum TranscriptionProvider: String, Codable, CaseIterable, Identifiable {
    case whisperCpp   // local, via whisper.cpp binary — accurate, fast
    case openRouter   // OpenRouter audio model (free options available)
    case openAI       // Whisper API
    case gemini       // Gemini audio understanding
    case ollamaAudio  // local multimodal LLM (gemma4 / gemma3n) — experimental
    var id: String { rawValue }
    var label: String {
        switch self {
        case .whisperCpp: return "whisper.cpp (local, recommended)"
        case .openRouter: return "OpenRouter (free audio models)"
        case .openAI: return "OpenAI Whisper"
        case .gemini: return "Gemini"
        case .ollamaAudio: return "Ollama audio LLM (experimental)"
        }
    }
}

enum LLMProviderKind: String, Codable, CaseIterable, Identifiable {
    case ollama   // local
    case openRouter
    case openAI
    case gemini
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ollama: return "Ollama (local)"
        case .openRouter: return "OpenRouter (free models)"
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
    var whisperLanguage: String = "auto" // "auto", "en", "hi", … (use a multilingual model for non-English)
    var whisperUseGPU = true             // turn off if whisper crashes on Metal/ggml init
    var ollamaBaseURL: String = "http://127.0.0.1:11434"
    var ollamaModel: String = "llama3.1"
    var ollamaTranscribeModel: String = ""   // empty = use ollamaModel
    var visionModel: String = ""             // screenshot analysis model; empty = use ollamaModel
    var autoCaptureScreen = false            // auto-snapshot the screen during a call
    var autoCaptureOnChange = true           // true = on screen change; false = on a timer
    var autoCaptureInterval: Double = 60     // seconds between timed auto-captures

    // Cloud keys (stored in UserDefaults for simplicity; move to Keychain for prod)
    var openAIKey: String = ""
    var openAIModel: String = "gpt-4o-mini"
    var openAITranscribeModel: String = "gpt-4o-mini-transcribe"  // faster/better than whisper-1
    var geminiKey: String = ""
    var geminiModel: String = "gemini-1.5-flash"
    var openRouterKey: String = ""
    var openRouterModel: String = "google/gemini-2.0-flash-exp:free"  // free + handles audio & text

    // Capture behaviour
    var captureMic = true
    var captureSystem = true
    var micDeviceUID = ""          // empty = system default input
    var autoStopOnSilence = true
    var silenceThreshold: Float = 0.012   // RMS below this counts as "quiet"
    var silenceTimeout: Double = 12        // seconds of quiet before auto-stop
    var maxChunkSeconds: Double = 30       // transcribe in ~30s batches
    var parallelTranscriptions = 3         // batch concurrency
    var customDataDirectory = ""           // empty = default Application Support
    var recordingRetentionDays = 1         // keep audio chunks this many days
    var maxStorageMB = 500                 // prune oldest recordings past this size

    // Owner / onboarding
    var ownerName = ""
    var onboarded = false
    var talkBack = false                    // speak Macda's chat replies aloud (talking mode)

    // Mascot appearance
    var mascotScale: Double = 0.62         // 0.4 (tiny) … 1.2 (big)
    var mascotColorHex = ""                // empty = default
    var mascotStyle = "bear"               // bear | cat | bunny | fox | robot
    var showMascot = true

    // Auto-listen
    var autoListen = false                 // start recording automatically on speech
    var autoListenThreshold: Float = 0.009 // RMS to count as speech (lower = more sensitive)

    // Voiceprints
    var voiceMatchThreshold: Float = 0.70  // cosine similarity to call it the same voice (lower = matches more readily)

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
        whisperLanguage         = s(.whisperLanguage, d.whisperLanguage)
        whisperUseGPU           = s(.whisperUseGPU, d.whisperUseGPU)
        ollamaBaseURL           = s(.ollamaBaseURL, d.ollamaBaseURL)
        ollamaModel             = s(.ollamaModel, d.ollamaModel)
        ollamaTranscribeModel   = s(.ollamaTranscribeModel, d.ollamaTranscribeModel)
        visionModel             = s(.visionModel, d.visionModel)
        autoCaptureScreen       = s(.autoCaptureScreen, d.autoCaptureScreen)
        autoCaptureOnChange     = s(.autoCaptureOnChange, d.autoCaptureOnChange)
        autoCaptureInterval     = s(.autoCaptureInterval, d.autoCaptureInterval)
        openAIKey               = s(.openAIKey, d.openAIKey)
        openAIModel             = s(.openAIModel, d.openAIModel)
        openAITranscribeModel   = s(.openAITranscribeModel, d.openAITranscribeModel)
        geminiKey               = s(.geminiKey, d.geminiKey)
        geminiModel             = s(.geminiModel, d.geminiModel)
        openRouterKey           = s(.openRouterKey, d.openRouterKey)
        openRouterModel         = s(.openRouterModel, d.openRouterModel)
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
        ownerName               = s(.ownerName, d.ownerName)
        onboarded               = s(.onboarded, d.onboarded)
        talkBack                = s(.talkBack, d.talkBack)
        mascotScale             = s(.mascotScale, d.mascotScale)
        mascotColorHex          = s(.mascotColorHex, d.mascotColorHex)
        mascotStyle             = s(.mascotStyle, d.mascotStyle)
        showMascot              = s(.showMascot, d.showMascot)
        autoListen              = s(.autoListen, d.autoListen)
        autoListenThreshold     = s(.autoListenThreshold, d.autoListenThreshold)
        voiceMatchThreshold     = s(.voiceMatchThreshold, d.voiceMatchThreshold)
        maxStorageMB            = s(.maxStorageMB, d.maxStorageMB)
    }
}
