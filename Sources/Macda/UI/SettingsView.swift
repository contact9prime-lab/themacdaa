import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var llmStatus: ConnectionStatus = .idle
    @State private var micDevices: [AudioInputDevice] = []
    @State private var ollamaModels: [String] = []
    @State private var openRouterModels: [OpenRouterModels.Model] = []

    private var s: Binding<Settings> {
        Binding(get: { appState.settings },
                set: { appState.settings = $0; appState.persistSettings() })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header("Settings", subtitle: "Bring your own models — local or cloud.")

                groupBox("Transcription (speech → text)") {
                    Picker("Engine", selection: s.transcriptionProvider) {
                        ForEach(TranscriptionProvider.allCases) { Text($0.label).tag($0) }
                    }
                    if appState.settings.transcriptionProvider == .openRouter {
                        openRouterControls(audioOnly: true)
                    }
                    if appState.settings.transcriptionProvider == .ollamaAudio {
                        ollamaModelControls(model: s.ollamaTranscribeModel,
                                            label: "Transcription model", allowSameAsNotes: true)
                        Label("Heads up: general LLMs (gemma4) often summarize or rephrase audio instead of transcribing it word-for-word — your notes end up as summaries. Use whisper.cpp for accurate transcripts. gemma3n is better than gemma4 if you want to try the LLM path.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if appState.settings.transcriptionProvider == .whisperCpp {
                        labeledField("whisper.cpp binary", text: s.whisperCppBinaryPath,
                                     hint: "e.g. /opt/homebrew/bin/whisper-cli")
                        labeledField("Model file (.bin)", text: s.whisperModelPath,
                                     hint: "ggml-small.bin (multilingual) or ggml-base.en.bin (English)")
                        Picker("Language", selection: s.whisperLanguage) {
                            Text("Auto-detect").tag("auto")
                            Text("English").tag("en")
                            Text("Hindi").tag("hi")
                            Text("Spanish").tag("es")
                            Text("French").tag("fr")
                            Text("German").tag("de")
                            Text("Chinese").tag("zh")
                            Text("Arabic").tag("ar")
                        }
                        Text("Non-English needs a multilingual model (e.g. ggml-small.bin). Setting the language explicitly is more reliable than auto-detect on short clips.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Use GPU (Metal)", isOn: s.whisperUseGPU)
                        Text("Turn this OFF if whisper crashes with a Metal/ggml error (some Homebrew builds have a buggy Metal backend). Macda also auto-falls back to CPU when it detects that crash.")
                            .font(.caption).foregroundStyle(.secondary)
                        statusBadge(appState.settings.whisperReady,
                                    ok: "whisper.cpp ready", bad: "Set binary + model for local transcription")
                    }
                }

                groupBox("Notes & to-dos (LLM)") {
                    Picker("Provider", selection: s.llmProvider) {
                        ForEach(LLMProviderKind.allCases) { Text($0.label).tag($0) }
                    }
                    if appState.settings.llmProvider == .openRouter {
                        openRouterControls(audioOnly: false)
                    }
                    if appState.settings.llmProvider == .ollama {
                        labeledField("Ollama URL", text: s.ollamaBaseURL,
                                     hint: "http://127.0.0.1:11434 — or http://<other-machine>:11434")
                        ollamaModelControls(model: s.ollamaModel, label: "Model")
                        Text("Running Ollama on another machine? Make sure it's started with `OLLAMA_HOST=0.0.0.0 ollama serve` so it accepts connections from this Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    connectionTester
                }

                groupBox("Screen artifacts (⌥⌘S)") {
                    Toggle("Auto-capture the screen during calls", isOn: s.autoCaptureScreen)
                    if appState.settings.autoCaptureScreen {
                        Picker("When", selection: s.autoCaptureOnChange) {
                            Text("When the screen changes").tag(true)
                            Text("On a timer").tag(false)
                        }
                        .pickerStyle(.radioGroup)
                        if !appState.settings.autoCaptureOnChange {
                            HStack {
                                Text("Every")
                                Slider(value: s.autoCaptureInterval, in: 15...300, step: 15)
                                Text("\(Int(appState.settings.autoCaptureInterval))s").monospacedDigit().frame(width: 44)
                            }
                        }
                        Text(appState.settings.autoCaptureOnChange
                             ? "While recording, Macda watches the screen and snapshots + analyzes it whenever it changes significantly (e.g. a new slide or app)."
                             : "While recording, Macda snapshots the screen on this interval and analyzes each into an artifact.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    if appState.settings.llmProvider == .ollama {
                        ollamaModelControls(model: s.visionModel, label: "Vision model", allowSameAsNotes: true)
                        Text("Use a vision-capable model (gemma4 understands images). ⌥⌘S captures the screen and analyzes it into an artifact.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        labeledField("Vision model", text: s.visionModel,
                                     hint: appState.settings.llmProvider == .openAI ? "gpt-4o-mini" : "gemini-1.5-flash")
                        Text("Screenshots are sent to your selected cloud provider's vision model.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                groupBox("Cloud keys (optional)") {
                    secureField("OpenAI API key", text: s.openAIKey)
                    labeledField("OpenAI chat model", text: s.openAIModel, hint: "gpt-4o-mini")
                    Divider()
                    secureField("Gemini API key", text: s.geminiKey)
                    labeledField("Gemini model", text: s.geminiModel, hint: "gemini-1.5-flash")
                    Text("Keys are stored in UserDefaults on this Mac. Audio is sent to these services only when you pick them.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                groupBox("Listening") {
                    Toggle("Capture microphone (your voice)", isOn: s.captureMic)
                    if appState.settings.captureMic {
                        HStack {
                            Picker("Microphone", selection: s.micDeviceUID) {
                                Text("System Default").tag("")
                                ForEach(micDevices) { Text($0.name).tag($0.uid) }
                            }
                            Button { micDevices = AudioDevices.inputDevices() } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Refresh device list")
                            .buttonStyle(.borderless)
                        }
                        HStack(spacing: 8) {
                            Text("Live input").font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: Double(min(appState.liveLevel, 1)))
                                .frame(maxWidth: 160)
                            Text(appState.isListening ? "listening" : "(start to test)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Choosing a mic here sets it as your Mac's default input (the reliable way to capture a specific device).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Capture system audio (others on the call)", isOn: s.captureSystem)
                    Toggle("Auto-stop when it goes quiet", isOn: s.autoStopOnSilence)
                    Toggle("Auto-listen — start automatically when I hear speech", isOn: Binding(
                        get: { appState.settings.autoListen },
                        set: { appState.setAutoListen($0) }))
                    if appState.settings.autoListen {
                        HStack {
                            Text("Sensitivity").font(.caption)
                            // Higher slider = more sensitive = lower RMS threshold.
                            Slider(value: Binding(
                                get: { Double(1 - (appState.settings.autoListenThreshold - 0.003) / 0.027) },
                                set: { appState.setAutoListenThreshold(Float(0.003 + (1 - $0) * 0.027)) }),
                                   in: 0...1)
                            Text(String(format: "rms %.3f", appState.settings.autoListenThreshold))
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary).frame(width: 64)
                        }
                        Text("If it only triggers when you talk loud or whistle, drag sensitivity up. Watch the “Auto-listen level” lines in the Logs tab to pick a value just above your silence level.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Silence timeout")
                        Slider(value: s.silenceTimeout, in: 4...60, step: 2)
                        Text("\(Int(appState.settings.silenceTimeout))s").monospacedDigit().frame(width: 38)
                    }
                    HStack {
                        Text("Parallel transcriptions")
                        Stepper("\(appState.settings.parallelTranscriptions)",
                                value: s.parallelTranscriptions, in: 1...8)
                    }
                    Text("System audio needs Screen Recording permission; the mic needs Microphone permission. macOS will ask the first time.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Text("Voice match").font(.caption)
                        Slider(value: Binding(
                            get: { Double(appState.settings.voiceMatchThreshold) },
                            set: { appState.settings.voiceMatchThreshold = Float($0); appState.persistSettings() }),
                               in: 0.5...0.9)
                        Text(String(format: "%.2f", appState.settings.voiceMatchThreshold)).monospacedDigit().frame(width: 44).font(.caption)
                    }
                    Text("Lower = recognizes the same voice more readily (but may merge similar voices); higher = stricter. Note: voiceprints are computed from mixed mic+system audio, so they're best-effort.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                groupBox("You & your buddy") {
                    labeledField("Your name (task owner)", text: s.ownerName, hint: "e.g. Piyush")
                    Text("Buddy").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(mascotStyles, id: \.id) { item in
                            Button { appState.setMascotStyle(item.id) } label: {
                                VStack(spacing: 3) {
                                    MascotBlob(mood: .idle, level: 0, blink: false, breathe: false,
                                               customHex: appState.settings.mascotColorHex, style: item.id)
                                        .frame(width: 40, height: 40)
                                    Text(item.name).font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                .padding(5)
                                .background(RoundedRectangle(cornerRadius: 9)
                                    .fill(appState.settings.mascotStyle == item.id ? Theme.chipAccentBg : .clear))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    Divider()
                    Toggle("Show the mascot on screen", isOn: Binding(
                        get: { appState.settings.showMascot },
                        set: { appState.setShowMascot($0) }))
                    HStack {
                        Text("Size")
                        Slider(value: s.mascotScale, in: 0.4...1.2)
                        Text(String(format: "%.0f%%", appState.settings.mascotScale * 100))
                            .monospacedDigit().frame(width: 44)
                    }
                    HStack(spacing: 8) {
                        Text("Color")
                        ForEach(Color.mascotPresets, id: \.hex) { preset in
                            Circle()
                                .fill(Color(hex: preset.hex) ?? .blue)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(.primary.opacity(
                                    appState.settings.mascotColorHex == preset.hex ? 0.9 : 0), lineWidth: 2))
                                .onTapGesture { appState.setMascotColor(preset.hex) }
                        }
                        Spacer()
                    }
                    Text("The mascot's idle color uses your pick; it still turns green while listening, amber while thinking, etc. You can also right-click the mascot for these.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                groupBox("Notifications") {
                    Text("Macda shows a banner when a task reminder is due — even when you're in another app.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Send test notification") {
                            Notifier.shared.notifyNow(title: "Macda", body: "Notifications are working ✅")
                        }
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                groupBox("Storage") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Data folder").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(appState.dataDirectory.path)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Reveal") { appState.revealDataFolder() }
                            Button("Change…") { chooseFolder() }
                        }
                        Text("Notes, meetings, people, and recordings are stored here. Changing the folder takes effect after relaunch.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Text("Keep recorded audio for")
                        Stepper("\(appState.settings.recordingRetentionDays) day\(appState.settings.recordingRetentionDays == 1 ? "" : "s")",
                                value: s.recordingRetentionDays, in: 1...30)
                        Spacer()
                        Text("Audio on disk: \(appState.recordingsSizeString())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Max storage")
                        Slider(value: Binding(
                            get: { Double(appState.settings.maxStorageMB) },
                            set: { appState.settings.maxStorageMB = Int($0); appState.persistSettings() }),
                               in: 100...5000, step: 100)
                        Text(appState.settings.maxStorageMB >= 1000
                             ? String(format: "%.1f GB", Double(appState.settings.maxStorageMB) / 1000)
                             : "\(appState.settings.maxStorageMB) MB")
                            .monospacedDigit().frame(width: 64)
                    }
                    Text("Audio chunks are kept so you can replay them and enroll voiceprints. They're pruned by age (above) and once the total passes the max size — oldest first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .onAppear {
            micDevices = AudioDevices.inputDevices()
            loadModels()
            if appState.settings.transcriptionProvider == .openRouter || appState.settings.llmProvider == .openRouter {
                Task { openRouterModels = await OpenRouterModels.list() }
            }
        }
    }

    // MARK: Connection test

    @ViewBuilder
    private var connectionTester: some View {
        Divider()
        HStack(spacing: 10) {
            Button {
                testNow()
            } label: {
                if llmStatus.isTesting {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Testing…") }
                } else {
                    Label("Test Connection", systemImage: "bolt.horizontal.circle")
                }
            }
            .disabled(llmStatus.isTesting)

            statusLabel
            Spacer()
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch llmStatus {
        case .idle:
            EmptyView()
        case .testing:
            EmptyView()
        case .ok(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .warn(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .fail(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func ollamaModelControls(model: Binding<String>, label: String, allowSameAsNotes: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { loadModels() } label: {
                    Label("Load list", systemImage: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.borderless)
            }
            if ollamaModels.isEmpty {
                TextField("e.g. gemma4:12b", text: model).textFieldStyle(.roundedBorder)
            } else {
                Picker("", selection: model) {
                    if allowSameAsNotes { Text("Same as notes model").tag("") }
                    ForEach(ollamaModels, id: \.self) { Text($0).tag($0) }
                    if !model.wrappedValue.isEmpty && !ollamaModels.contains(model.wrappedValue) {
                        Text("\(model.wrappedValue) — not installed").tag(model.wrappedValue)
                    }
                }
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func openRouterControls(audioOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            secureField("OpenRouter API key", text: s.openRouterKey)
            HStack {
                Text("Model").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { openRouterModels = await OpenRouterModels.list() } } label: {
                    Label("Load free models", systemImage: "arrow.clockwise").font(.caption)
                }.buttonStyle(.borderless)
            }
            let free = openRouterModels.filter { $0.free && (!audioOnly || $0.audio) }
            if free.isEmpty {
                TextField("google/gemini-2.0-flash-exp:free", text: s.openRouterModel).textFieldStyle(.roundedBorder)
            } else {
                Picker("", selection: s.openRouterModel) {
                    ForEach(free) { Text($0.name + ($0.audio ? "  🎧" : "")).tag($0.id) }
                    if !free.contains(where: { $0.id == appState.settings.openRouterModel }) {
                        Text(appState.settings.openRouterModel).tag(appState.settings.openRouterModel)
                    }
                }.labelsHidden()
            }
            Text("Showing only **free** models\(audioOnly ? " that accept audio (🎧)" : ""). Get a key at openrouter.ai/keys.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func loadModels() {
        let url = appState.settings.ollamaBaseURL
        Task { @MainActor in
            let models = await OllamaModels.list(baseURL: url)
            ollamaModels = models
            // If the configured notes model isn't actually installed, auto-select
            // a real one so notes/transcription work without manual fiddling.
            if !models.isEmpty, !models.contains(appState.settings.ollamaModel) {
                appState.settings.ollamaModel = models.first { $0.lowercased().contains("gemma") } ?? models[0]
                appState.persistSettings()
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose where Macda stores its data"
        if panel.runModal() == .OK, let url = panel.url {
            appState.setCustomDataDirectory(url.path)
        }
    }

    private func testNow() {
        let settings = appState.settings
        llmStatus = .testing
        Task {
            let result = await ConnectionTester(settings: settings).testLLM()
            await MainActor.run { llmStatus = result }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func groupBox<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(hint, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            SecureField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func statusBadge(_ ok: Bool, ok okText: String, bad: String) -> some View {
        Label(ok ? okText : bad, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(ok ? .green : .orange)
    }
}
