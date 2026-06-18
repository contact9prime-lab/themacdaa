import Foundation
import Combine
import AppKit
import AVFoundation

/// What the mascot is doing right now — drives the animation + menu bar glyph.
enum MacdaMood: Equatable {
    case idle           // sleeping / blinking
    case listening      // ears up, bouncing
    case thinking       // transcribing / calling the LLM
    case happy          // just saved notes
    case error(String)  // something went wrong
}

@MainActor
final class AppState: ObservableObject {
    // MARK: Published UI state
    @Published var mood: MacdaMood = .idle
    @Published var isListening = false
    @Published var liveLevel: Float = 0          // 0...1 mic energy for the animation
    @Published var transcribingCount = 0         // chunks in flight → "working" animation
    @Published var partialTranscript: String = ""
    @Published var statusLine: String = "Hi, I'm Macda 👋"
    @Published var selectedTab: DashboardTab = .chat

    // MARK: Data
    @Published var meetings: [Meeting] = []
    @Published var notes: [NoteItem] = []
    @Published var todos: [TodoItem] = []
    @Published var people: [Person] = []
    @Published var pendingVoices: [PendingVoice] = []
    @Published var activeMeeting: Meeting?
    @Published var settings: Settings = .load()

    /// Set by AppDelegate so the mascot's right-click menu can open the dashboard.
    var openDashboard: ((DashboardTab?) -> Void)?

    // Chat with the on-device agent.
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatBusy = false
    private lazy var agent = AgentEngine(appState: self)

    // MARK: Services
    private let store = Store()
    private lazy var capture = AudioCaptureEngine()
    private lazy var pipeline = TranscriptionPipeline()
    private lazy var autoListenMonitor = AutoListenMonitor()
    private var transcriptBuffer = TranscriptBuffer()
    private var cancellables = Set<AnyCancellable>()
    private var inFlight: [Task<Void, Never>] = []
    private var sessionSegments: [VoiceSegment] = []   // per-chunk voiceprints for speaker ID

    func bootstrap() {
        meetings = store.loadMeetings()
        notes = store.loadNotes()
        todos = store.loadTodos()
        chatMessages = store.loadChat()
        people = store.loadPeople()
        pendingVoices = store.loadPendingVoices()
        pruneStorage()
        autodetectWhisper()
        settings.save()          // migrate to on-disk settings.json immediately
        wireCaptureCallbacks()
        applyAutoListen()
        statusLine = settings.transcriptionProvider == .whisperCpp && !settings.whisperReady
            ? "Tip: set the whisper.cpp path in Settings for local transcription."
            : "Ready when you are. ⌥Space to start listening."
    }

    /// Fill in whisper.cpp paths automatically if they're missing, so local
    /// transcription works out of the box once whisper-cpp + a model are present.
    private func autodetectWhisper() {
        var changed = false
        if !FileManager.default.isExecutableFile(atPath: settings.whisperCppBinaryPath) {
            for candidate in ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
            where FileManager.default.isExecutableFile(atPath: candidate) {
                settings.whisperCppBinaryPath = candidate; changed = true; break
            }
        }
        if settings.whisperModelPath.isEmpty || !FileManager.default.fileExists(atPath: settings.whisperModelPath) {
            let modelsDir = (NSHomeDirectory() as NSString).appendingPathComponent("models")
            if let found = (try? FileManager.default.contentsOfDirectory(atPath: modelsDir))?
                .filter({ $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") })
                .sorted().first {
                settings.whisperModelPath = (modelsDir as NSString).appendingPathComponent(found)
                changed = true
            }
        }
        if changed { settings.save() }
    }

    func shutdown() {
        if isListening { stopListening(save: false) }
        settings.save()
    }

    // MARK: - Listening control

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func startListening(for meeting: Meeting? = nil) {
        guard !isListening else { return }
        autoListenMonitor.stop()    // free the mic for the full capture engine
        activeMeeting = meeting ?? defaultMeeting()
        transcriptBuffer.reset()
        sessionSegments.removeAll()
        partialTranscript = ""
        isListening = true
        mood = .listening
        statusLine = "Listening… I'll take notes."
        pipeline.configure(with: settings)

        Task {
            do {
                try await capture.start(sources: settings.audioSources)
            } catch {
                await MainActor.run {
                    self.mood = .error(error.localizedDescription)
                    self.statusLine = "Couldn't start audio: \(error.localizedDescription)"
                    self.isListening = false
                }
            }
        }
    }

    func stopListening(save: Bool = true) {
        guard isListening else { return }
        isListening = false
        capture.stop()
        mood = .thinking
        liveLevel = 0
        statusLine = "Wrapping up… transcribing the tail."

        // Snapshot any final audio and the in-flight transcriptions.
        let tail = capture.flushPendingChunk()
        let pending = inFlight
        inFlight.removeAll()

        Task {
            // Let already-running chunk transcriptions finish, then the tail.
            for task in pending { await task.value }
            if let tail {
                let text = await pipeline.transcribe(tail)
                transcriptBuffer.append(text)
            }
            if save {
                await finalizeMeeting()
            } else {
                await MainActor.run { self.mood = .idle; self.partialTranscript = "" }
            }
            await MainActor.run {
                self.pruneStorage()             // keep audio under age + size caps
                self.applyAutoListen()          // resume monitoring if enabled
            }
        }
    }

    // MARK: - Capture wiring

    private var lastTranscribeErrorAt: Date?

    private func wireCaptureCallbacks() {
        // Surface transcription failures (e.g. "model not found") instead of
        // silently producing no text.
        pipeline.onError = { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                let now = Date()
                if let last = self.lastTranscribeErrorAt, now.timeIntervalSince(last) < 4 { return }
                self.lastTranscribeErrorAt = now
                self.statusLine = "Transcription error: \(message)"
                self.mood = .error(message)
            }
        }

        // Live audio level → animation.
        capture.onLevel = { [weak self] level in
            Task { @MainActor in self?.liveLevel = level }
        }
        // A finished audio chunk (cut on silence or max length) → transcription.
        capture.onChunk = { [weak self] chunk in
            Task { @MainActor in self?.handleChunk(chunk) }
        }
        // Silence detector decided the call went quiet for a while.
        capture.onSilenceTimeout = { [weak self] in
            Task { @MainActor in
                guard let self, self.isListening, self.settings.autoStopOnSilence else { return }
                self.statusLine = "Got quiet — pausing. ⌥Space to resume."
                self.stopListening()
            }
        }
        capture.onError = { [weak self] message in
            Task { @MainActor in
                self?.mood = .error(message)
                self?.statusLine = message
            }
        }
    }

    /// Transcribe a chunk and fold it into the live transcript. Tracked so stop
    /// can wait for everything in flight before finalizing.
    private func handleChunk(_ chunk: AudioChunk) {
        transcribingCount += 1                  // mascot shows it's working
        let task = Task { [weak self] in
            guard let self else { return }
            let text = await self.pipeline.transcribe(chunk)
            await MainActor.run {
                self.transcribingCount = max(0, self.transcribingCount - 1)
                guard !text.isEmpty else { return }
                self.transcriptBuffer.append(text)
                self.partialTranscript = self.transcriptBuffer.recentTail()
                if !chunk.embedding.isEmpty {
                    self.sessionSegments.append(VoiceSegment(embedding: chunk.embedding, text: text))
                }
            }
        }
        inFlight.append(task)
        inFlight.removeAll { $0.isCancelled }
    }

    // MARK: - Finalize → notes/todos via the LLM

    private func finalizeMeeting() async {
        let transcript = transcriptBuffer.fullText()
        guard !transcript.isEmpty else {
            await MainActor.run { self.statusLine = "Nothing to note — silence the whole time." }
            return
        }
        await MainActor.run { self.statusLine = "Thinking up notes & to-dos…" }

        let extractor = NoteExtractor(settings: settings)
        let knownPeople = people
        do {
            let result = try await extractor.extract(transcript: transcript,
                                                     meeting: activeMeeting,
                                                     knownPeople: knownPeople)
            // Identify speakers acoustically from the session's voiceprints.
            let segments = sessionSegments
            let speakers = VoiceMatcher(threshold: settings.voiceMatchThreshold)
                .assign(segments: segments, people: knownPeople)
            await MainActor.run {
                self.applyExtraction(result, transcript: transcript, speakers: speakers)
                let newVoices = self.surfaceNewVoices(speakers)
                self.mood = .happy
                self.statusLine = newVoices > 0
                    ? "Saved notes & to-dos ✨  \(newVoices) new voice\(newVoices == 1 ? "" : "s") to tag."
                    : "Saved \(result.notes.count) notes & \(result.todos.count) to-dos ✨"
            }
            // Settle back to idle after a beat.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { if !self.isListening { self.mood = .idle } }
        } catch {
            await MainActor.run {
                // Even if the LLM fails, keep the raw transcript so nothing is lost.
                self.saveRawTranscriptFallback(transcript)
                self.mood = .error(error.localizedDescription)
                self.statusLine = "LLM error — saved raw transcript instead."
            }
        }
    }

    private func applyExtraction(_ result: ExtractionResult, transcript: String, speakers: [DetectedSpeaker]) {
        let now = Date()
        var meeting = activeMeeting ?? defaultMeeting()
        meeting.transcript = transcript
        meeting.summary = result.summary
        meeting.endedAt = now
        meeting.speakers = speakers
        upsertMeeting(meeting)

        for n in result.notes {
            notes.insert(NoteItem(text: n, meetingID: meeting.id, createdAt: now), at: 0)
        }
        for t in result.todos {
            todos.insert(TodoItem(title: t.title, due: t.due, meetingID: meeting.id, createdAt: now), at: 0)
        }
        store.saveNotes(notes)
        store.saveTodos(todos)
    }

    private func saveRawTranscriptFallback(_ transcript: String) {
        var meeting = activeMeeting ?? defaultMeeting()
        meeting.transcript = transcript
        meeting.endedAt = Date()
        upsertMeeting(meeting)
        notes.insert(NoteItem(text: "Raw transcript (LLM unavailable):\n\(transcript)",
                              meetingID: meeting.id, createdAt: Date()), at: 0)
        store.saveNotes(notes)
    }

    // MARK: - Meetings

    func defaultMeeting() -> Meeting {
        Meeting(title: "Untitled call", startedAt: Date())
    }

    func registerMeeting(_ meeting: Meeting) {
        upsertMeeting(meeting)
    }

    func upsertMeeting(_ meeting: Meeting) {
        if let idx = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[idx] = meeting
        } else {
            meetings.insert(meeting, at: 0)
        }
        if activeMeeting?.id == meeting.id { activeMeeting = meeting }
        store.saveMeetings(meetings)
    }

    func deleteMeeting(_ meeting: Meeting) {
        meetings.removeAll { $0.id == meeting.id }
        store.saveMeetings(meetings)
    }

    // MARK: - People & voices

    /// Add unrecognized speakers to the pending-voices list (with their
    /// voiceprint, so tagging enrolls it). Returns how many were new.
    private func surfaceNewVoices(_ speakers: [DetectedSpeaker]) -> Int {
        let title = activeMeeting?.title ?? "Untitled call"
        var added = 0
        for s in speakers where s.personID == nil {
            let already = pendingVoices.contains {
                $0.label.caseInsensitiveCompare(s.label) == .orderedSame && $0.meetingID == activeMeeting?.id
            }
            guard !already else { continue }
            pendingVoices.insert(PendingVoice(label: s.label, sampleQuote: s.sampleQuote,
                                              embedding: s.embedding,
                                              meetingID: activeMeeting?.id, meetingTitle: title), at: 0)
            added += 1
        }
        if added > 0 { store.savePendingVoices(pendingVoices) }
        return added
    }

    func person(matching label: String) -> Person? {
        let l = label.lowercased()
        return people.first { p in
            p.name.lowercased() == l || p.aliases.contains { $0.lowercased() == l }
        }
    }

    func addPerson(_ person: Person) {
        people.insert(person, at: 0)
        store.savePeople(people)
    }

    func updatePerson(_ person: Person) {
        if let idx = people.firstIndex(where: { $0.id == person.id }) { people[idx] = person }
        store.savePeople(people)
    }

    func deletePerson(_ person: Person) {
        people.removeAll { $0.id == person.id }
        store.savePeople(people)
    }

    /// Tag a surfaced voice to a person (existing or newly created). The voice's
    /// embedding is enrolled as/merged into that person's voiceprint so the same
    /// voice is recognized automatically in future calls.
    func tagVoice(_ voice: PendingVoice, toExisting personID: UUID) {
        guard var person = people.first(where: { $0.id == personID }) else { return }
        if voice.label.lowercased() != person.name.lowercased(),
           !person.aliases.contains(where: { $0.lowercased() == voice.label.lowercased() }) {
            person.aliases.append(voice.label)
        }
        person.voicePrint = mergeVoiceprint(existing: person.voicePrint, new: voice.embedding)
        updatePerson(person)
        linkSpeakerInMeetings(label: voice.label, meetingID: voice.meetingID, personID: personID)
        dismissVoice(voice)
    }

    func tagVoiceAsNewPerson(_ voice: PendingVoice, name: String) {
        var person = Person(name: name, aliases: voice.label.lowercased() == name.lowercased() ? [] : [voice.label])
        person.voicePrint = voice.embedding
        addPerson(person)
        linkSpeakerInMeetings(label: voice.label, meetingID: voice.meetingID, personID: person.id)
        dismissVoice(voice)
    }

    private func mergeVoiceprint(existing: [Float], new: [Float]) -> [Float] {
        guard !new.isEmpty else { return existing }
        guard !existing.isEmpty else { return new }
        return VoiceEmbedder.centroid([existing, new])
    }

    func dismissVoice(_ voice: PendingVoice) {
        pendingVoices.removeAll { $0.id == voice.id }
        store.savePendingVoices(pendingVoices)
    }

    private func linkSpeakerInMeetings(label: String, meetingID: UUID?, personID: UUID) {
        guard let meetingID, let idx = meetings.firstIndex(where: { $0.id == meetingID }) else { return }
        for s in meetings[idx].speakers.indices where meetings[idx].speakers[s].label.lowercased() == label.lowercased() {
            meetings[idx].speakers[s].personID = personID
        }
        store.saveMeetings(meetings)
    }

    // MARK: - Todos

    func toggleTodo(_ todo: TodoItem) {
        guard let idx = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[idx].done.toggle()
        store.saveTodos(todos)
    }

    func addManualNote(_ text: String) {
        notes.insert(NoteItem(text: text, meetingID: activeMeeting?.id, createdAt: Date()), at: 0)
        store.saveNotes(notes)
    }

    func persistSettings() {
        settings.save()
        pipeline.configure(with: settings)
    }

    // MARK: - Mascot appearance

    func setMascotScale(_ s: Double) { settings.mascotScale = s; settings.save() }
    func setMascotColor(_ hex: String) { settings.mascotColorHex = hex; settings.save() }
    func setShowMascot(_ v: Bool) { settings.showMascot = v; settings.save() }

    // MARK: - Auto-listen

    func setAutoListen(_ on: Bool) {
        settings.autoListen = on
        settings.save()
        applyAutoListen()
    }

    /// Start/stop the background speech monitor based on the setting & state.
    private func applyAutoListen() {
        autoListenMonitor.onSpeech = { [weak self] in
            guard let self, self.settings.autoListen, !self.isListening else { return }
            self.statusLine = "Heard something — listening automatically."
            self.startListening()
        }
        guard settings.autoListen && !isListening else {
            autoListenMonitor.stop()
            return
        }
        // The monitor taps the mic, so it needs Microphone permission too.
        Task {
            let granted = await Self.ensureMicAccess()
            await MainActor.run {
                guard self.settings.autoListen, !self.isListening else { return }
                guard granted else {
                    self.statusLine = "Auto-listen needs Microphone permission (System Settings → Privacy)."
                    return
                }
                let ok = self.autoListenMonitor.start(threshold: self.settings.silenceThreshold,
                                                      micDeviceUID: self.settings.micDeviceUID)
                if ok {
                    if self.mood == .idle { self.statusLine = "Auto-listen on — I'll start when I hear you." }
                } else {
                    self.statusLine = "Auto-listen couldn't open the mic — check the device in Settings."
                }
            }
        }
    }

    static func ensureMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: - Storage location

    var dataDirectory: URL { store.baseDirectory }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.baseDirectory])
    }

    func recordingsSizeString() -> String {
        ByteCountFormatter.string(fromByteCount: store.recordingsByteSize(), countStyle: .file)
    }

    /// Apply both retention (age) and the storage cap (size) to recordings.
    func pruneStorage() {
        store.cleanupOldRecordings(maxAge: Double(max(1, settings.recordingRetentionDays)) * 86_400)
        store.enforceStorageCap(maxBytes: Int64(max(50, settings.maxStorageMB)) * 1_000_000)
    }

    /// Point Macda at a new data folder. Takes effect after relaunch.
    func setCustomDataDirectory(_ path: String) {
        settings.customDataDirectory = path
        settings.save()
    }

    // MARK: - Chat agent

    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chatBusy else { return }
        let historyBefore = chatMessages
        chatMessages.append(ChatMessage(role: .user, text: trimmed))
        chatBusy = true
        store.saveChat(chatMessages)

        Task {
            await agent.respond(to: trimmed, history: historyBefore) { [weak self] message in
                guard let self else { return }
                self.chatMessages.append(message)
                self.store.saveChat(self.chatMessages)
            }
            self.chatBusy = false
        }
    }

    func clearChat() {
        chatMessages.removeAll()
        store.saveChat(chatMessages)
    }

    /// Called by the agent after it mutates notes/todos via a tool.
    func persistChatData() {
        store.saveTodos(todos)
        store.saveNotes(notes)
    }
}
