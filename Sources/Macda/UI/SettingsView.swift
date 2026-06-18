import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var llmStatus: ConnectionStatus = .idle
    @State private var micDevices: [AudioInputDevice] = []
    @State private var ollamaModels: [String] = []

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
                                     hint: "e.g. ~/models/ggml-base.en.bin")
                        statusBadge(appState.settings.whisperReady,
                                    ok: "whisper.cpp ready", bad: "Set binary + model for local transcription")
                    }
                }

                groupBox("Notes & to-dos (LLM)") {
                    Picker("Provider", selection: s.llmProvider) {
                        ForEach(LLMProviderKind.allCases) { Text($0.label).tag($0) }
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
                    }
                    Toggle("Capture system audio (others on the call)", isOn: s.captureSystem)
                    Toggle("Auto-stop when it goes quiet", isOn: s.autoStopOnSilence)
                    Toggle("Auto-listen — start automatically when I hear speech", isOn: Binding(
                        get: { appState.settings.autoListen },
                        set: { appState.setAutoListen($0) }))
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
                }

                groupBox("Mascot") {
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
        .onAppear { micDevices = AudioDevices.inputDevices(); loadModels() }
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
