import SwiftUI

/// Talk to Macda. The agent reads (and can edit) your local notes, to-dos, and
/// meetings — everything stays on your Mac when you use Ollama.
struct ChatView: View {
    @ObservedObject var appState: AppState
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                header("Chat", subtitle: "Ask about your meetings, notes & to-dos — or tell me to add things.")
                Spacer()
                Button { appState.clearChat() } label: { Image(systemName: "trash") }
                    .help("Clear conversation")
                    .padding(.trailing).padding(.top)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if appState.chatMessages.isEmpty { suggestions }
                        ForEach(appState.chatMessages) { bubble($0) }
                        if appState.chatBusy {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Macda is thinking…").font(.caption).foregroundStyle(.secondary)
                            }
                            .id("busy")
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
    }

    // MARK: Bubbles

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(m.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
        case .assistant:
            HStack {
                Text(m.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 40)
            }
        case .tool:
            Text(m.text)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking:").font(.caption).foregroundStyle(.secondary)
            ForEach(["What did I commit to in my last meeting?",
                     "Summarize my open to-dos",
                     "Add a to-do: send the deck by Friday",
                     "What notes mention pricing?"], id: \.self) { s in
                Button { draft = s; send() } label: {
                    Text(s).font(.callout)
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message Macda…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit(send)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || appState.chatBusy)
        }
        .padding(10)
        .background(.bar)
    }

    private func send() {
        let text = draft
        draft = ""
        appState.sendChat(text)
    }
}
