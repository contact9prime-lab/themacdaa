import SwiftUI

struct PeopleView: View {
    @ObservedObject var appState: AppState
    @State private var showingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                header("People", subtitle: "Who's on your calls. Tag voices so Macda knows who said what.")
                Spacer()
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .padding(.trailing).padding(.top)
            }

            List {
                if !appState.pendingVoices.isEmpty {
                    Section("🔊 New voices to tag") {
                        ForEach(appState.pendingVoices) { voice in
                            PendingVoiceRow(voice: voice, appState: appState)
                        }
                    }
                }

                Section(appState.people.isEmpty ? "" : "Known people") {
                    if appState.people.isEmpty {
                        Text("No people yet. Add teammates, or tag a voice after a call.")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                    ForEach(appState.people) { person in
                        PersonRow(person: person, appState: appState)
                    }
                }
            }
            .listStyle(.inset)
        }
        .sheet(isPresented: $showingNew) {
            PersonEditor(appState: appState, person: Person(name: ""))
        }
    }
}

struct PendingVoiceRow: View {
    let voice: PendingVoice
    @ObservedObject var appState: AppState
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "waveform.badge.questionmark").foregroundStyle(.orange)
                Text(voice.label).font(.headline)
                Spacer()
                Text(voice.meetingTitle).font(.caption).foregroundStyle(.secondary)
            }
            if !voice.sampleQuote.isEmpty {
                Text("“\(voice.sampleQuote)”").font(.callout).italic().foregroundStyle(.secondary)
            }
            if !voice.embedding.isEmpty {
                Label("Tagging enrolls this voiceprint for auto-recognition next time",
                      systemImage: "waveform.badge.plus")
                    .font(.caption2).foregroundStyle(.blue)
            }
            HStack(spacing: 8) {
                if !appState.people.isEmpty {
                    Menu("Tag as existing") {
                        ForEach(appState.people) { p in
                            Button(p.name) { appState.tagVoice(voice, toExisting: p.id) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                TextField("New person name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onSubmit(createNew)
                Button("Add", action: createNew).disabled(newName.isEmpty)
                Spacer()
                Button("Ignore") { appState.dismissVoice(voice) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func createNew() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        appState.tagVoiceAsNewPerson(voice, name: name)
        newName = ""
    }
}

struct PersonRow: View {
    let person: Person
    @ObservedObject var appState: AppState
    @State private var editing = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(.tint.opacity(0.25))
                .frame(width: 34, height: 34)
                .overlay(Text(initials).font(.caption.bold()))
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.headline)
                if !person.role.isEmpty {
                    Text(person.role).font(.caption).foregroundStyle(.secondary)
                }
                if !person.aliases.isEmpty {
                    Text("aka " + person.aliases.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if person.hasVoiceprint {
                    Label("Voiceprint enrolled — auto-recognized", systemImage: "waveform.badge.mic")
                        .font(.caption2).foregroundStyle(.green)
                }
            }
            Spacer()
            Button { editing = true } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
            Button(role: .destructive) { appState.deletePerson(person) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $editing) { PersonEditor(appState: appState, person: person) }
    }

    private var initials: String {
        let parts = person.name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

struct PersonEditor: View {
    @ObservedObject var appState: AppState
    @State var person: Person
    @State private var aliasText = ""
    @Environment(\.dismiss) private var dismiss

    private var isNew: Bool { !appState.people.contains { $0.id == person.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Person" : "Edit Person").font(.title2.bold())
            Form {
                TextField("Name", text: $person.name)
                TextField("Role (optional)", text: $person.role)
                TextField("Voice note (how they sound / accent)", text: $person.voiceNote)
                TextField("Aliases (comma separated)", text: $aliasText)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(person.name.isEmpty)
            }
        }
        .padding(20).frame(width: 420)
        .onAppear { aliasText = person.aliases.joined(separator: ", ") }
    }

    private func save() {
        person.aliases = aliasText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if isNew { appState.addPerson(person) } else { appState.updatePerson(person) }
        dismiss()
    }
}
