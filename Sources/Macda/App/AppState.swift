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
    @Published var liveTick = 0                  // increments every second while recording (drives the menu-bar timer)
    @Published var transcribingCount = 0         // chunks in flight → "working" animation
    @Published var partialTranscript: String = ""
    @Published var livePreview: String = ""      // in-progress utterance, refreshes ~1.5s
    @Published var batchProgress: Double = 0     // 0…1 toward the next 30s batch
    private var previewBusy = false
    @Published var statusLine: String = "Hi, I'm Macda 👋"
    @Published var selectedTab: DashboardTab = .chat

    // MARK: Data
    @Published var meetings: [Meeting] = []
    @Published var notes: [NoteItem] = []
    @Published var todos: [TodoItem] = []
    @Published var people: [Person] = []
    @Published var pendingVoices: [PendingVoice] = []
    @Published var artifacts: [Artifact] = []
    @Published var showCaptureBubble = false     // show the latest capture in the mascot bubble
    @Published var minimized = false             // shrink to a tiny dock when idle
    private var captureBubbleTimer: Timer?
    private var idleTicks = 0
    private var idleTimer: Timer?
    @Published var activeMeeting: Meeting?
    @Published var settings: Settings = .load()

    /// Set by AppDelegate so the mascot's right-click menu can open the dashboard.
    var openDashboard: ((DashboardTab?) -> Void)?
    var openLiveView: (() -> Void)?

    // Chat with the on-device agent.
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatBusy = false
    @Published var dictating = false
    private lazy var agent = AgentEngine(appState: self)
    private let speaker = Speaker()
    private let recorder = SimpleRecorder()

    // MARK: Services
    private let store = Store()
    private lazy var capture = AudioCaptureEngine()
    private lazy var pipeline = TranscriptionPipeline()
    private lazy var autoListenMonitor = AutoListenMonitor()
    private var transcriptBuffer = TranscriptBuffer()
    private var cancellables = Set<AnyCancellable>()
    private var inFlight: [Task<Void, Never>] = []
    private var sessionSegments: [VoiceSegment] = []   // per-chunk voiceprints for speaker ID
    private var sessionAudioFiles: [String] = []       // chunk WAV paths for this session
    private var autoCaptureTimer: Timer?
    private var pendingExtractions: [PendingExtraction] = []
    private var retryTimer: Timer?
    private var recordingStartedAt: Date?     // when the current recording actually began
    private var uiTickTimer: Timer?

    func bootstrap() {
        meetings = store.loadMeetings()
        notes = store.loadNotes()
        todos = store.loadTodos()
        chatMessages = store.loadChat()
        people = store.loadPeople()
        pendingVoices = store.loadPendingVoices()
        artifacts = store.loadArtifacts()
        pendingExtractions = store.loadPending()
        pruneStorage()
        autodetectWhisper()
        settings.save()          // migrate to on-disk settings.json immediately
        wireCaptureCallbacks()
        applyAutoListen()
        startReminderTimer()
        startRetryTimer()
        startIdleTimer()
        // Retry any queued extractions shortly after launch.
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); await processPending() }
        // Re-arm notifications for upcoming tasks once auth has settled.
        Task { try? await Task.sleep(nanoseconds: 4_000_000_000); rescheduleAllNotifications() }
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
        recordingStartedAt = Date()
        liveTick = 0
        uiTickTimer?.invalidate()
        uiTickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.liveTick += 1 }
        }
        transcriptBuffer.reset()
        sessionSegments.removeAll()
        sessionAudioFiles.removeAll()
        partialTranscript = ""
        livePreview = ""
        batchProgress = 0
        isListening = true
        mood = .listening
        statusLine = "Listening… I'll take notes."
        pipeline.configure(with: settings)
        Log.info("Listening started · meeting='\(activeMeeting?.title ?? "?")' · transcriber=\(settings.transcriptionProvider.rawValue) · sources=\(settings.audioSources.rawValue)")
        startAutoCapture()

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
        autoCaptureTimer?.invalidate(); autoCaptureTimer = nil
        uiTickTimer?.invalidate(); uiTickTimer = nil
        mood = .thinking
        liveLevel = 0
        livePreview = ""
        batchProgress = 0
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
            Log.error("Transcription error: \(message)")
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
        // Live, in-progress transcript for the mascot bubble (refreshes quickly).
        capture.onPreview = { [weak self] chunk in
            Task { @MainActor in self?.handlePreview(chunk) }
        }
        // Progress toward the next batch → dashboard progress bar.
        capture.onBatchProgress = { [weak self] p in
            Task { @MainActor in self?.batchProgress = p }
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
                if text.isEmpty {
                    Log.info("Batch \(chunk.index) transcribed: (no speech)")
                    return
                }
                Log.info("Batch \(chunk.index) transcribed (\(text.count) chars): \(text.prefix(80))")
                self.transcriptBuffer.append(text)
                self.partialTranscript = self.transcriptBuffer.recentTail()
                self.livePreview = ""    // committed text now includes it
                if !chunk.embedding.isEmpty {
                    self.sessionSegments.append(VoiceSegment(embedding: chunk.embedding,
                                                             text: text,
                                                             audioPath: chunk.url.path))
                }
                self.sessionAudioFiles.append(chunk.url.path)
            }
        }
        inFlight.append(task)
        inFlight.removeAll { $0.isCancelled }
    }

    /// Transcribe the in-progress audio for a live bubble update. Drops overlaps
    /// so it never backs up behind itself.
    private func handlePreview(_ chunk: AudioChunk) {
        guard !previewBusy else { return }
        previewBusy = true
        Task { [weak self] in
            guard let self else { return }
            let text = await self.pipeline.transcribePreview(chunk)
            await MainActor.run {
                self.previewBusy = false
                if self.isListening, !text.isEmpty { self.livePreview = text }
            }
        }
    }

    // MARK: - Finalize → notes/todos via the LLM

    private func finalizeMeeting() async {
        let transcript = transcriptBuffer.fullText()
        guard !transcript.isEmpty else {
            await MainActor.run { self.statusLine = "Nothing to note — silence the whole time." }
            return
        }
        // Save the meeting (with transcript + speakers) FIRST so nothing is lost.
        let knownPeople = people
        let speakers = VoiceMatcher(threshold: settings.voiceMatchThreshold)
            .assign(segments: sessionSegments, people: knownPeople)
        var meeting = activeMeeting ?? defaultMeeting()
        meeting.transcript = transcript
        meeting.endedAt = Date()
        meeting.speakers = speakers
        meeting.audioFiles = sessionAudioFiles
        await MainActor.run {
            self.upsertMeeting(meeting)
            _ = self.surfaceNewVoices(speakers)
            self.statusLine = "Thinking up notes & to-dos…"
        }

        let ok = await runExtraction(transcript: transcript, meetingID: meeting.id, people: knownPeople)
        await MainActor.run {
            if ok {
                self.mood = .happy
            } else {
                // LLM unavailable — queue for automatic retry.
                self.enqueuePending(meetingID: meeting.id, transcript: transcript)
                self.mood = .error("LLM unavailable")
                self.statusLine = "LLM unavailable — I'll retry the notes in a few minutes."
            }
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        await MainActor.run { if !self.isListening { self.mood = .idle } }
    }

    /// Run note extraction for a transcript and apply it to the meeting.
    /// Returns false if the LLM failed (so it can be queued/retried).
    private func runExtraction(transcript: String, meetingID: UUID, people: [Person]) async -> Bool {
        let extractor = NoteExtractor(settings: settings)
        let meeting = meetings.first { $0.id == meetingID }
        do {
            let result = try await extractor.extract(transcript: transcript, meeting: meeting, knownPeople: people)
            await MainActor.run { self.applyExtraction(result, toMeetingID: meetingID) }
            Log.info("Extracted \(result.notes.count) notes, \(result.todos.count) to-dos for meeting \(meetingID).")
            return true
        } catch {
            Log.error("Note extraction failed: \(error.localizedDescription)")
            return false
        }
    }

    private func applyExtraction(_ result: ExtractionResult, toMeetingID id: UUID) {
        let now = Date()
        guard var meeting = meetings.first(where: { $0.id == id }) else { return }
        meeting.summary = result.summary
        upsertMeeting(meeting)
        // Replace any "pending" placeholder notes for this meeting.
        notes.removeAll { $0.meetingID == id && $0.tags.contains("Pending") }
        for n in result.notes {
            var tags = n.tags
            if !meeting.title.isEmpty, meeting.title != "Untitled call" { tags.append(meeting.title) }
            notes.insert(NoteItem(text: n.text, tags: tags, meetingID: id, createdAt: now), at: 0)
        }
        for t in result.todos {
            let me = ownerDisplayName
            var assignee = t.owner ?? me
            if ["me", "i", "myself", "mine"].contains(assignee.lowercased()) { assignee = me }
            let todo = TodoItem(title: t.title, assignee: assignee, due: t.due, meetingID: id, createdAt: now)
            todos.insert(todo, at: 0)
            scheduleNotification(for: todo)
        }
        store.saveNotes(notes)
        store.saveTodos(todos)
    }

    /// Re-run the LLM on a meeting's transcript (manual "re-generate notes").
    func reprocessMeeting(_ meeting: Meeting) {
        guard !meeting.transcript.isEmpty else { return }
        statusLine = "Re-generating notes for \(meeting.title)…"
        let people = self.people
        Task {
            let ok = await runExtraction(transcript: meeting.transcript, meetingID: meeting.id, people: people)
            await MainActor.run {
                self.statusLine = ok ? "Re-generated notes for \(meeting.title) ✨" : "Couldn't reach the LLM — try again."
            }
        }
    }

    // MARK: - Retry queue

    private func enqueuePending(meetingID: UUID, transcript: String) {
        pendingExtractions.removeAll { $0.meetingID == meetingID }
        pendingExtractions.append(PendingExtraction(meetingID: meetingID, transcript: transcript))
        store.savePending(pendingExtractions)
        // A visible placeholder so the meeting isn't blank.
        if !notes.contains(where: { $0.meetingID == meetingID && $0.tags.contains("Pending") }) {
            notes.insert(NoteItem(text: "⏳ Notes pending — the LLM was unavailable. Retrying automatically.",
                                  tags: ["Pending"], meetingID: meetingID, createdAt: Date()), at: 0)
            store.saveNotes(notes)
        }
    }

    private func startRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.processPending() }
        }
    }

    func processPending() async {
        guard !pendingExtractions.isEmpty else { return }
        Log.info("Retrying \(pendingExtractions.count) pending extraction(s).")
        for item in pendingExtractions {
            let ok = await runExtraction(transcript: item.transcript, meetingID: item.meetingID, people: people)
            await MainActor.run {
                if ok {
                    self.pendingExtractions.removeAll { $0.id == item.id }
                } else if let idx = self.pendingExtractions.firstIndex(where: { $0.id == item.id }) {
                    self.pendingExtractions[idx].attempts += 1
                }
                self.store.savePending(self.pendingExtractions)
            }
        }
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
                                              sampleAudioPath: s.sampleAudioPath,
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
        let saved = store.copyVoiceSample(from: voice.sampleAudioPath, personID: person.id)
        if !saved.isEmpty { person.voiceSamplePath = saved }
        updatePerson(person)
        linkSpeakerInMeetings(label: voice.label, meetingID: voice.meetingID, personID: personID)
        dismissVoice(voice)
    }

    func tagVoiceAsNewPerson(_ voice: PendingVoice, name: String) {
        var person = Person(name: name, aliases: voice.label.lowercased() == name.lowercased() ? [] : [voice.label])
        person.voicePrint = voice.embedding
        person.voiceSamplePath = store.copyVoiceSample(from: voice.sampleAudioPath, personID: person.id)
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
        scheduleNotification(for: todos[idx])   // cancels if now done
    }

    /// Fired when a task's reminder time arrives — AppDelegate shows a popup.
    var onDueReminder: ((TodoItem) -> Void)?
    private var reminderTimer: Timer?

    func addTodo(_ title: String, due: Date?) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let todo = TodoItem(title: t, assignee: ownerDisplayName, due: due,
                            meetingID: activeMeeting?.id, createdAt: Date())
        todos.insert(todo, at: 0)
        store.saveTodos(todos)
        scheduleNotification(for: todo)
    }

    func snoozeTodo(_ todo: TodoItem, minutes: Int) {
        guard let idx = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[idx].due = Date().addingTimeInterval(Double(minutes) * 60)
        todos[idx].reminded = false
        store.saveTodos(todos)
        scheduleNotification(for: todos[idx])
    }

    /// Schedule (or cancel) a macOS notification for a task's due time.
    private func scheduleNotification(for todo: TodoItem) {
        let id = todo.id.uuidString
        guard let due = todo.due, !todo.done, due > Date() else {
            Notifier.shared.cancel(id: id)
            return
        }
        Notifier.shared.scheduleReminder(id: id, title: "⏰ Macda reminder", body: todo.title, at: due)
    }

    func rescheduleAllNotifications() {
        for todo in todos { scheduleNotification(for: todo) }
    }

    /// Runs every 30s: fire a popup for tasks whose due time has arrived.
    private func startReminderTimer() {
        reminderTimer?.invalidate()
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkReminders() }
        }
    }

    private func checkReminders() {
        let now = Date()
        for idx in todos.indices {
            let t = todos[idx]
            guard !t.done, !t.reminded, let due = t.due, due <= now else { continue }
            todos[idx].reminded = true
            store.saveTodos(todos)
            // The OS handles authorized banners; only pop the in-app reminder
            // when system notifications aren't authorized (avoids double-alerts).
            if !Notifier.shared.authorized { onDueReminder?(todos[idx]) }
        }
    }

    func reassignTodo(_ todo: TodoItem, to name: String) {
        guard let idx = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[idx].assignee = name
        store.saveTodos(todos)
    }

    func deleteTodo(_ todo: TodoItem) {
        todos.removeAll { $0.id == todo.id }
        store.saveTodos(todos)
        Notifier.shared.cancel(id: todo.id.uuidString)
    }

    // MARK: - Owner / onboarding

    var ownerDisplayName: String { settings.ownerName.isEmpty ? "You" : settings.ownerName }

    // MARK: - Idle shrink

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickIdle() }
        }
    }

    private func tickIdle() {
        let busy = isListening || transcribingCount > 0 || showCaptureBubble || !overdueTodos.isEmpty
        if busy || mood != .idle {
            idleTicks = 0
            if minimized { minimized = false }
            return
        }
        idleTicks += 1
        if idleTicks >= 6, !minimized { minimized = true }   // ~30s idle → shrink
    }

    /// Called when the user hovers/interacts with the mascot — wakes it up.
    func wakeMascot() {
        idleTicks = 0
        if minimized { minimized = false }
    }

    /// Names you can assign tasks to: you + known people.
    var assignableNames: [String] {
        var names = [ownerDisplayName]
        names.append(contentsOf: people.map(\.name).filter { $0.caseInsensitiveCompare(ownerDisplayName) != .orderedSame })
        return names
    }

    func completeOnboarding(name: String, style: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        settings.ownerName = trimmed
        settings.mascotStyle = style
        settings.onboarded = true
        settings.save()
        if !trimmed.isEmpty, !people.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            people.insert(Person(name: trimmed, role: "You (owner)"), at: 0)
            store.savePeople(people)
        }
        statusLine = trimmed.isEmpty ? "Hi! 👋" : "Hi \(trimmed)! 👋 I'm Macda."
    }

    /// Incomplete tasks whose due date is before today.
    var overdueTodos: [TodoItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return todos.filter { todo in
            guard !todo.done, let due = todo.due else { return false }
            return Calendar.current.startOfDay(for: due) < today
        }
    }

    func addManualNote(_ text: String) {
        notes.insert(NoteItem(text: text, tags: ["Manual"], meetingID: activeMeeting?.id, createdAt: Date()), at: 0)
        store.saveNotes(notes)
    }

    func deleteNote(_ note: NoteItem) {
        notes.removeAll { $0.id == note.id }
        store.saveNotes(notes)
    }

    func updateNoteText(_ note: NoteItem, text: String) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx].text = text
        store.saveNotes(notes)
    }

    func updateTodoTitle(_ todo: TodoItem, title: String) {
        guard let idx = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[idx].title = title
        store.saveTodos(todos)
    }

    func persistSettings() {
        settings.save()
        pipeline.configure(with: settings)
    }

    /// Full committed transcript of the current session (for the live view).
    func currentTranscript() -> String { transcriptBuffer.fullText() }

    var liveElapsedString: String {
        // Always measure from when recording actually started (not the meeting's
        // registration time) so every timer agrees.
        guard let start = recordingStartedAt else { return "00:00" }
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - Mascot appearance

    func setMascotScale(_ s: Double) { settings.mascotScale = s; settings.save() }
    func setMascotColor(_ hex: String) { settings.mascotColorHex = hex; settings.save() }
    func setMascotStyle(_ style: String) { settings.mascotStyle = style; settings.save() }
    func setShowMascot(_ v: Bool) { settings.showMascot = v; settings.save() }

    // MARK: - Auto-listen

    func setAutoListen(_ on: Bool) {
        settings.autoListen = on
        settings.save()
        applyAutoListen()
    }

    /// Update auto-listen sensitivity and restart the monitor so it takes effect.
    func setAutoListenThreshold(_ threshold: Float) {
        settings.autoListenThreshold = threshold
        settings.save()
        if settings.autoListen && !isListening {
            autoListenMonitor.stop()
            applyAutoListen()
        }
    }

    /// Start/stop the background speech monitor based on the setting & state.
    private func applyAutoListen() {
        autoListenMonitor.onSpeech = { [weak self] in
            guard let self, self.settings.autoListen, !self.isListening else { return }
            Log.info("Auto-listen: heard speech → starting session.")
            self.statusLine = "Heard something — listening automatically."
            self.startListening()
        }
        guard settings.autoListen && !isListening else {
            autoListenMonitor.stop()
            return
        }
        Log.info("Auto-listen: enabling background monitor.")
        // The monitor taps the mic, so it needs Microphone permission too.
        Task {
            let granted = await Self.ensureMicAccess()
            await MainActor.run {
                guard self.settings.autoListen, !self.isListening else { return }
                guard granted else {
                    Log.error("Auto-listen: Microphone permission not granted.")
                    self.statusLine = "Auto-listen needs Microphone permission (System Settings → Privacy)."
                    return
                }
                let ok = self.autoListenMonitor.start(threshold: self.settings.autoListenThreshold,
                                                      micDeviceUID: self.settings.micDeviceUID)
                if ok {
                    if self.mood == .idle { self.statusLine = "Auto-listen on — I'll start when I hear you." }
                } else {
                    Log.error("Auto-listen: monitor failed to start (mic device issue).")
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

    // MARK: - Screen artifacts

    /// Capture a screenshot, store it, and analyze it with the vision model.
    func captureScreenshot() {
        statusLine = "📸 Capturing screen…"
        // Show it in the mascot bubble for a while (works with or without a call).
        showCaptureBubble = true
        captureBubbleTimer?.invalidate()
        captureBubbleTimer = Timer.scheduledTimer(withTimeInterval: 16, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.showCaptureBubble = false }
        }
        let meetingID = activeMeeting?.id
        let settingsSnapshot = settings
        Task {
            do {
                let png = try await ScreenshotCapture.capturePNG()
                let id = UUID()
                let url = store.artifactsDir.appendingPathComponent("\(id.uuidString).png")
                try png.write(to: url, options: .atomic)
                var artifact = Artifact(id: id, imagePath: url.path, meetingID: meetingID, analyzing: true)
                await MainActor.run {
                    self.artifacts.insert(artifact, at: 0)
                    self.store.saveArtifacts(self.artifacts)
                    self.statusLine = "🧠 Analyzing the screenshot…"
                }
                let text = (try? await VisionAnalyzer(settings: settingsSnapshot).analyze(pngData: png)) ?? ""
                artifact.aiText = text
                artifact.analyzing = false
                await MainActor.run {
                    if let idx = self.artifacts.firstIndex(where: { $0.id == id }) { self.artifacts[idx] = artifact }
                    self.store.saveArtifacts(self.artifacts)
                    self.statusLine = text.isEmpty ? "Saved screenshot (no analysis)." : "Saved screen artifact 🖼️"
                }
            } catch {
                await MainActor.run {
                    self.mood = .error(error.localizedDescription)
                    self.statusLine = "Screenshot failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private var lastScreenSignature: [UInt8] = []
    private var lastAutoCaptureAt: Date?

    /// Snapshot the screen during a call — on significant change, or on a timer.
    private func startAutoCapture() {
        autoCaptureTimer?.invalidate()
        lastScreenSignature = []
        lastAutoCaptureAt = nil
        guard settings.autoCaptureScreen else { return }

        if settings.autoCaptureOnChange {
            Log.info("Auto-capture: on screen change")
            autoCaptureTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.checkScreenChange() }
            }
        } else {
            let interval = max(15, settings.autoCaptureInterval)
            Log.info("Auto-capture: every \(Int(interval))s")
            autoCaptureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isListening else { return }
                    self.captureScreenshot()
                }
            }
        }
    }

    private func checkScreenChange() async {
        guard isListening, settings.autoCaptureScreen, settings.autoCaptureOnChange else { return }
        guard let sig = try? await ScreenshotCapture.captureLumaSignature() else { return }
        defer { lastScreenSignature = sig }
        guard !lastScreenSignature.isEmpty else { return }   // first sample = baseline
        let diff = ScreenshotCapture.difference(sig, lastScreenSignature)
        // Don't fire more than once per 10s, and only on a meaningful change.
        let recently = lastAutoCaptureAt.map { Date().timeIntervalSince($0) < 10 } ?? false
        if diff > 12 && !recently {
            lastAutoCaptureAt = Date()
            Log.info(String(format: "Auto-capture: screen changed (diff %.1f) → snapshot", diff))
            captureScreenshot()
        }
    }

    func deleteArtifact(_ artifact: Artifact) {
        try? FileManager.default.removeItem(atPath: artifact.imagePath)
        artifacts.removeAll { $0.id == artifact.id }
        store.saveArtifacts(artifacts)
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
                // Talking mode: read assistant replies aloud.
                if self.settings.talkBack, message.role == .assistant {
                    self.speaker.speak(message.text)
                }
            }
            self.chatBusy = false
        }
    }

    func setTalkBack(_ on: Bool) {
        settings.talkBack = on
        settings.save()
        if !on { speaker.stop() }
    }

    // MARK: - Dictation (voice → chat)

    func toggleDictation() {
        dictating ? stopDictation() : startDictation()
    }

    private func startDictation() {
        Task {
            let granted = await Self.ensureMicAccess()
            await MainActor.run {
                guard granted, self.recorder.start() else {
                    self.statusLine = "Mic needed for talking."
                    return
                }
                self.dictating = true
                self.speaker.stop()
            }
        }
    }

    private func stopDictation() {
        dictating = false
        guard let url = recorder.stop() else { return }
        pipeline.configure(with: settings)
        Task {
            let chunk = AudioChunk(url: url, index: -2, duration: 0)
            let text = await pipeline.transcribe(chunk)
            await MainActor.run {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { self.sendChat(t) }
                else { self.statusLine = "Didn't catch that — try again." }
            }
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
