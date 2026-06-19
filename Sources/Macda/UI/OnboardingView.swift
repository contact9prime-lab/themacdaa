import SwiftUI
import AppKit

let mascotStyles: [(id: String, name: String)] = [
    ("bear", "Bear"), ("cat", "Cat"), ("bunny", "Bunny"), ("fox", "Fox"), ("robot", "Robot")
]

/// A clean, multi-step setup: identity → transcription → notes LLM → permissions.
struct OnboardingView: View {
    @ObservedObject var appState: AppState
    var onDone: () -> Void

    @State private var step = 0
    @State private var name = ""
    @State private var style = "bear"
    private let steps = ["Welcome", "Transcription", "Notes & Chat", "Finish"]

    private func bind<T>(_ kp: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { appState.settings[keyPath: kp] },
                set: { appState.settings[keyPath: kp] = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            ScrollView {
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: transcriptionStep
                    case 2: llmStep
                    default: finishStep
                    }
                }
                .padding(20)
            }
            Divider().overlay(Theme.hairline)
            footer
        }
        .frame(width: 480, height: 600)
        .background(Theme.cream)
        .preferredColorScheme(.light)
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 12) {
            MascotBlob(mood: .happy, level: 0, blink: false, breathe: true,
                       customHex: appState.settings.mascotColorHex, style: style)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up Macda").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                Text(steps[step]).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(steps.indices, id: \.self) { i in
                    Circle().fill(i == step ? Theme.accent : Theme.hairline).frame(width: 7, height: 7)
                }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if step > 0 { Button("Back") { step -= 1 } }
            Spacer()
            if step < steps.count - 1 {
                Button("Next") { step += 1 }.buttonStyle(MacdaButtonStyle()).frame(width: 120)
                    .disabled(step == 0 && name.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button("Finish") { finish() }.buttonStyle(MacdaButtonStyle()).frame(width: 120)
            }
        }
        .padding(14)
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hi, I'm Macda 👋").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
            Text("I sit in on your calls, take notes, track to-dos, and you can chat with everything — all on your Mac.")
                .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            field("What should I call you?", "Your name — tasks default to you", bind(\.ownerName))
                .onChange(of: appState.settings.ownerName) { _, v in name = v }
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick your buddy").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                HStack(spacing: 10) {
                    ForEach(mascotStyles, id: \.id) { item in
                        Button { style = item.id; appState.settings.mascotStyle = item.id } label: {
                            VStack(spacing: 3) {
                                MascotBlob(mood: .idle, level: 0, blink: false, breathe: false,
                                           customHex: appState.settings.mascotColorHex, style: item.id)
                                    .frame(width: 42, height: 42)
                                Text(item.name).font(.system(size: 9)).foregroundStyle(Theme.inkSoft)
                            }
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: 9)
                                .fill(style == item.id ? Theme.chipAccentBg : .clear))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { name = appState.settings.ownerName; style = appState.settings.mascotStyle }
    }

    private var transcriptionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How should I turn speech into text?").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            Picker("Engine", selection: bind(\.transcriptionProvider)) {
                ForEach(TranscriptionProvider.allCases) { Text($0.label).tag($0) }
            }
            switch appState.settings.transcriptionProvider {
            case .whisperCpp:
                statusLine(appState.settings.whisperReady,
                           ok: "whisper.cpp ready — fully local & free",
                           bad: "whisper.cpp not set up yet (Settings can auto-detect, or use the installer).")
            case .openRouter:
                secure("OpenRouter API key", bind(\.openRouterKey))
                field("Model", "google/gemini-2.0-flash-exp:free", bind(\.openRouterModel))
                hint("Free audio models available — get a key at openrouter.ai/keys.")
            case .openAI:
                secure("OpenAI API key", bind(\.openAIKey))
            case .gemini:
                secure("Gemini API key", bind(\.geminiKey))
            case .ollamaAudio:
                hint("Uses your Ollama server (set below). gemma4 can be hit-or-miss for transcription.")
            }
            hint("whisper.cpp (local) is the most reliable and private. You can change this anytime in Settings.")
        }
    }

    private var llmStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which AI writes the notes & answers your questions?").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
            Picker("Provider", selection: bind(\.llmProvider)) {
                ForEach(LLMProviderKind.allCases) { Text($0.label).tag($0) }
            }
            switch appState.settings.llmProvider {
            case .ollama:
                field("Ollama URL", "http://127.0.0.1:11434 or a remote host", bind(\.ollamaBaseURL))
                field("Model", "llama3.1 / gemma2 / qwen2.5", bind(\.ollamaModel))
                hint("Fully local & free. Run `OLLAMA_HOST=0.0.0.0 ollama serve` for a remote machine.")
            case .openRouter:
                secure("OpenRouter API key", bind(\.openRouterKey))
                field("Model", "google/gemini-2.0-flash-exp:free", bind(\.openRouterModel))
                hint("Free models available — get a key at openrouter.ai/keys.")
            case .openAI:
                secure("OpenAI API key", bind(\.openAIKey))
                field("Model", "gpt-4o-mini", bind(\.openAIModel))
            case .gemini:
                secure("Gemini API key", bind(\.geminiKey))
                field("Model", "gemini-1.5-flash", bind(\.geminiModel))
            }
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're all set, \(appState.settings.ownerName.isEmpty ? "friend" : appState.settings.ownerName)! 🎉")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 8) {
                bullet("⌥Space starts/stops listening; the mascot floats on the right edge.")
                bullet("⌥⌘D opens the dashboard; ⌥⌘S captures the screen.")
                bullet("macOS will ask for Microphone (and Screen Recording for system audio) the first time — please allow them.")
                bullet("Tweak anything later in Settings.")
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).macdaCard()
        }
    }

    // MARK: Bits

    private func field(_ title: String, _ hint: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
            TextField(hint, text: binding).textFieldStyle(.roundedBorder)
        }
    }
    private func secure(_ title: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
            SecureField(title, text: binding).textFieldStyle(.roundedBorder)
        }
    }
    private func hint(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(Theme.inkSoft)
    }
    private func bullet(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(Theme.accent)
            Text(t).font(.system(size: 12)).foregroundStyle(Theme.ink)
        }
    }
    private func statusLine(_ ok: Bool, ok okText: String, bad: String) -> some View {
        Label(ok ? okText : bad, systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(ok ? .green : .orange)
    }

    private func finish() {
        appState.persistSettings()
        appState.completeOnboarding(name: appState.settings.ownerName, style: style)
        onDone()
    }
}

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) { self.appState = appState }

    func show() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.backgroundColor = NSColor(Theme.cream)
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.contentView = NSHostingView(rootView: OnboardingView(appState: appState) { [weak self] in
            self?.window?.close()
            self?.window = nil
        })
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
