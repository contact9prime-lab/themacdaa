import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(DashboardTab.allCases, selection: Binding(
                get: { appState.selectedTab },
                set: { if let v = $0 { appState.selectedTab = v } })
            ) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(170)
            .safeAreaInset(edge: .bottom) { listenButton }
        } detail: {
            Group {
                switch appState.selectedTab {
                case .chat: ChatView(appState: appState)
                case .notes: NotesView(appState: appState)
                case .todos: TodosView(appState: appState)
                case .meetings: MeetingsView(appState: appState)
                case .people: PeopleView(appState: appState)
                case .settings: SettingsView(appState: appState)
                }
            }
            .frame(minWidth: 480, minHeight: 460)
        }
    }

    private var listenButton: some View {
        Button {
            appState.toggleListening()
        } label: {
            Label(appState.isListening ? "Stop Listening" : "Start Listening",
                  systemImage: appState.isListening ? "stop.circle.fill" : "mic.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .tint(appState.isListening ? .red : .accentColor)
        .buttonStyle(.borderedProminent)
        .padding(10)
    }
}

// MARK: - Notes

struct NotesView: View {
    @ObservedObject var appState: AppState
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Notes", subtitle: "Auto-captured from your calls — plus anything you jot down.")
            HStack {
                TextField("Quick note…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(draft.isEmpty)
            }
            .padding(.horizontal)

            if appState.notes.isEmpty {
                emptyState("No notes yet", "Start a call and I'll fill this in.")
            } else {
                List {
                    ForEach(appState.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.text).font(.body).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appState.addManualNote(text)
        draft = ""
    }
}

// MARK: - Todos

struct TodosView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("To-Dos", subtitle: "Action items Macda heard you agree to.")
            if appState.todos.isEmpty {
                emptyState("Nothing to do 🎉", "Action items from calls land here.")
            } else {
                List {
                    ForEach(appState.todos) { todo in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                appState.toggleTodo(todo)
                            } label: {
                                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todo.done ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(todo.title)
                                    .strikethrough(todo.done)
                                    .foregroundStyle(todo.done ? .secondary : .primary)
                                if let due = todo.due {
                                    Text("Due \(due, style: .date)")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Shared bits

@ViewBuilder
func header(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.largeTitle.bold())
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding([.horizontal, .top])
    .padding(.bottom, 8)
}

@ViewBuilder
func emptyState(_ title: String, _ subtitle: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(.secondary)
        Text(title).font(.headline)
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
