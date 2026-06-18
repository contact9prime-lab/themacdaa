import SwiftUI

/// Ask Macda — chat over your local data, warm bubbles + tool-trace pills.
struct ChatView: View {
    @ObservedObject var appState: AppState
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().overlay(Theme.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if appState.chatMessages.isEmpty { suggestions }
                        ForEach(appState.chatMessages) { bubble($0) }
                        if appState.chatBusy {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Macda is thinking…").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                            }.id("busy")
                        }
                    }
                    .padding()
                }
                .onChange(of: appState.chatMessages.count) { _, _ in
                    withAnimation { proxy.scrollTo(appState.chatMessages.last?.id, anchor: .bottom) }
                }
            }
            inputBar
        }
        .background(Theme.cream)
    }

    private var chatHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.accent)
                Circle().fill(.white).frame(width: 5, height: 5).offset(x: -4)
                Circle().fill(.white).frame(width: 5, height: 5).offset(x: 4)
            }.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ask Macda").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                HStack(spacing: 4) {
                    Image(systemName: appState.settings.llmProvider == .ollama ? "lock.fill" : "cloud.fill")
                        .font(.system(size: 9))
                    Text(providerLabel).font(.system(size: 11))
                }.foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button { appState.clearChat() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.cream)
    }

    private var providerLabel: String {
        switch appState.settings.llmProvider {
        case .ollama: return "On your Mac · Ollama"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(m.text).font(.system(size: 13)).foregroundStyle(.white)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .assistant:
            HStack {
                Text(m.text).font(.system(size: 13)).foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .frame(maxWidth: 460, alignment: .leading)
                    .macdaCard(Theme.card, radius: 14)
                Spacer(minLength: 40)
            }
        case .tool:
            Chip(text: toolSummary(m.text), systemImage: "wrench.adjustable", kind: .neutral)
                .padding(.leading, 2)
        }
    }

    /// Compress the verbose tool trace into a short pill like the mockup.
    private func toolSummary(_ raw: String) -> String {
        if let range = raw.range(of: "🔧 ") {
            let rest = raw[range.upperBound...]
            if let paren = rest.firstIndex(of: "(") { return "used " + rest[..<paren] }
        }
        return String(raw.prefix(40))
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking:").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
            ForEach(["What did I commit to in my last meeting?",
                     "Summarize my open to-dos",
                     "What was on screen today?",
                     "Add a to-do: send the deck by Friday"], id: \.self) { s in
                Button { draft = s; send() } label: {
                    Text(s).font(.system(size: 13)).foregroundStyle(Theme.accentDeep)
                }.buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message Macda…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline))
                .lineLimit(1...4).onSubmit(send)
            Button { send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || appState.chatBusy)
        }
        .padding(12).background(Theme.sand)
    }

    private func send() {
        let text = draft; draft = ""
        appState.sendChat(text)
    }
}
