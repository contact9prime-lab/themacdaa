import SwiftUI

struct DashboardView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.hairline)
            VStack(spacing: 0) {
                if appState.isListening || appState.transcribingCount > 0 { liveStrip }
                detail
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.cream)
        }
        .background(Theme.cream)
        .preferredColorScheme(.light)
    }

    // Live transcription strip — shows while listening on every tab.
    private var liveStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                Text(appState.isListening ? "Listening" : "Wrapping up")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentDeep)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(appState.liveElapsedString).font(.system(size: 12)).foregroundStyle(Theme.inkSoft).monospacedDigit()
                }
                Spacer()
                if appState.transcribingCount > 0 {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                        Text("transcribing \(appState.transcribingCount)").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            // Progress toward the next 30s batch — fills, then a new entry arrives.
            ProgressView(value: appState.batchProgress)
                .tint(Theme.accent)
            if !liveText.isEmpty {
                Text(liveText).font(.system(size: 12)).foregroundStyle(Theme.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.liveHighlight)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.accentSoft.opacity(0.5)), alignment: .bottom)
    }

    private var liveText: String {
        [appState.partialTranscript, appState.livePreview]
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ").suffix(180).description
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
        case .logs: LogsView()
        case .settings: SettingsView(appState: appState)
        }
    }
}

// MARK: - Notes

struct NotesView: View {
    @ObservedObject var appState: AppState
    @State private var draft = ""
    @State private var editingID: UUID?
    @State private var editText = ""

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
                            VStack(alignment: .leading, spacing: 6) {
                                if editingID == note.id {
                                    TextEditor(text: $editText)
                                        .font(.system(size: 13)).frame(minHeight: 60)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline))
                                    HStack {
                                        Spacer()
                                        Button("Cancel") { editingID = nil }
                                        Button("Save") { appState.updateNoteText(note, text: editText); editingID = nil }
                                            .keyboardShortcut(.defaultAction)
                                    }
                                } else {
                                    HStack(alignment: .top) {
                                        Text(note.text).font(.system(size: 13)).foregroundStyle(Theme.ink)
                                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                        Spacer()
                                        Button { editingID = note.id; editText = note.text } label: {
                                            Image(systemName: "pencil").font(.system(size: 11))
                                        }.buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
                                        Button(role: .destructive) { appState.deleteNote(note) } label: {
                                            Image(systemName: "trash").font(.system(size: 11))
                                        }.buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
                                    }
                                    if !note.tags.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 5) {
                                                ForEach(note.tags, id: \.self) { Chip(text: $0, kind: .neutral) }
                                            }
                                        }
                                    }
                                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                                }
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
    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var newTitle = ""
    @State private var newDue = Date().addingTimeInterval(3600)
    @State private var withDue = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("To-Dos", subtitle: "Action items Macda heard you agree to — add your own with a reminder.")
            HStack(spacing: 8) {
                TextField("New task…", text: $newTitle).textFieldStyle(.roundedBorder).onSubmit(add)
                Toggle("Remind", isOn: $withDue).toggleStyle(.checkbox)
                if withDue {
                    DatePicker("", selection: $newDue, in: Date()...)
                        .labelsHidden().datePickerStyle(.compact)
                }
                Button("Add", action: add).disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal).padding(.bottom, 8)

            if appState.todos.isEmpty {
                emptyState("Nothing to do 🎉", "Action items from calls land here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.todos) { todo in
                            todoRow(todo)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func add() {
        appState.addTodo(newTitle, due: withDue ? newDue : nil)
        newTitle = ""
    }

    private func isOverdue(_ todo: TodoItem) -> Bool {
        guard !todo.done, let due = todo.due else { return false }
        return due < Date()
    }

    @ViewBuilder
    private func todoRow(_ todo: TodoItem) -> some View {
        let overdue = isOverdue(todo)
        HStack(alignment: .top, spacing: 10) {
            Button { appState.toggleTodo(todo) } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.done ? Theme.chipGreenInk : Theme.inkSoft)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                if editingID == todo.id {
                    HStack {
                        TextField("Task", text: $editText).textFieldStyle(.roundedBorder)
                            .onSubmit { appState.updateTodoTitle(todo, title: editText); editingID = nil }
                        Button("Save") { appState.updateTodoTitle(todo, title: editText); editingID = nil }
                        Button("Cancel") { editingID = nil }
                    }
                } else {
                    Text(todo.title).font(.system(size: 13))
                        .strikethrough(todo.done)
                        .foregroundStyle(todo.done ? Theme.inkSoft : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    if !todo.assignee.isEmpty {
                        Chip(text: todo.assignee, systemImage: "person.fill", kind: .green)
                    }
                    if let due = todo.due {
                        Chip(text: (overdue ? "Overdue " : "Due ") + due.formatted(.dateTime.month(.abbreviated).day()),
                             systemImage: "calendar", kind: overdue ? .accent : .neutral)
                    }
                }
            }
            Spacer()

            Menu {
                Section("Assign to") {
                    ForEach(appState.assignableNames, id: \.self) { name in
                        Button(name) { appState.reassignTodo(todo, to: name) }
                    }
                }
            } label: {
                Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton).frame(width: 22)

            Button { editingID = todo.id; editText = todo.title } label: {
                Image(systemName: "pencil").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.inkSoft)

            Button(role: .destructive) { appState.deleteTodo(todo) } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
        }
        .padding(12).macdaCard()
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(overdue ? .orange.opacity(0.6) : .clear, lineWidth: 1.5))
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
