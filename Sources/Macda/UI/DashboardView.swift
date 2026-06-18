import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.hairline)
            detail
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cream)
        }
        .background(Theme.cream)
        .preferredColorScheme(.light)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Theme.accent)
                    Circle().fill(.white).frame(width: 6, height: 6).offset(x: -5)
                    Circle().fill(.white).frame(width: 6, height: 6).offset(x: 5)
                }
                .frame(width: 28, height: 28)
                Text("Macda").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)

            ForEach(DashboardTab.allCases) { tab in
                navItem(tab)
            }

            Spacer()

            Button { appState.toggleListening() } label: {
                Label(appState.isListening ? "Stop listening" : "Start listening",
                      systemImage: appState.isListening ? "stop.fill" : "circle.fill")
            }
            .buttonStyle(MacdaButtonStyle())
            .padding(.horizontal, 12)

            Text("⌥Space")
                .font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.top, 6).padding(.bottom, 12)
        }
        .frame(width: 200)
        .background(Theme.sand)
    }

    private func navItem(_ tab: DashboardTab) -> some View {
        let selected = appState.selectedTab == tab
        return Button { appState.selectedTab = tab } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol).font(.system(size: 13)).frame(width: 18)
                Text(tab.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                if tab == .people && !appState.pendingVoices.isEmpty {
                    Text("\(appState.pendingVoices.count)")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                }
            }
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.accent : .clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selectedTab {
        case .chat: ChatView(appState: appState)
        case .notes: NotesView(appState: appState)
        case .todos: TodosView(appState: appState)
        case .meetings: MeetingsView(appState: appState)
        case .people: PeopleView(appState: appState)
        case .artifacts: ArtifactsView(appState: appState)
        case .settings: SettingsView(appState: appState)
        }
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
                TextField("Quick note…", text: $draft).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Add", action: add).disabled(draft.isEmpty)
            }
            .padding(.horizontal)

            if appState.notes.isEmpty {
                emptyState("No notes yet", "Start a call and I'll fill this in.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(appState.notes) { note in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(note.text).font(.system(size: 13)).foregroundStyle(Theme.ink)
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .macdaCard()
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        appState.addManualNote(text); draft = ""
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
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.todos) { todo in
                            HStack(alignment: .top, spacing: 10) {
                                Button { appState.toggleTodo(todo) } label: {
                                    Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(todo.done ? Theme.chipGreenInk : Theme.inkSoft)
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(todo.title).font(.system(size: 13))
                                        .strikethrough(todo.done)
                                        .foregroundStyle(todo.done ? Theme.inkSoft : Theme.ink)
                                    if let due = todo.due {
                                        Text("Due \(due, style: .date)").font(.system(size: 11)).foregroundStyle(Theme.accentDeep)
                                    }
                                }
                                Spacer()
                            }
                            .padding(12).macdaCard()
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Shared

@ViewBuilder
func header(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.ink)
        Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding([.horizontal, .top]).padding(.bottom, 10)
}

@ViewBuilder
func emptyState(_ title: String, _ subtitle: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(Theme.accentSoft)
        Text(title).font(.headline).foregroundStyle(Theme.ink)
        Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
