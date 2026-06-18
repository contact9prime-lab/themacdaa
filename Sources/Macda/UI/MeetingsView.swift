import SwiftUI

struct MeetingsView: View {
    @ObservedObject var appState: AppState
    @State private var showingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                header("Meetings", subtitle: "Register what you're about to join so notes get the right context.")
                Spacer()
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .padding(.trailing).padding(.top)
            }

            if appState.meetings.isEmpty {
                emptyState("No meetings yet", "Tap + to register one before your call.")
            } else {
                List {
                    ForEach(appState.meetings) { meeting in
                        MeetingRow(meeting: meeting, appState: appState)
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingNew) {
            MeetingEditor(appState: appState)
        }
    }
}

struct MeetingRow: View {
    let meeting: Meeting
    @ObservedObject var appState: AppState
    @State private var showTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meeting.title).font(.headline)
                Spacer()
                if appState.activeMeeting?.id == meeting.id && appState.isListening {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            HStack(spacing: 8) {
                Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(meeting.durationString).font(.caption).foregroundStyle(.secondary)
                if !meeting.attendees.isEmpty {
                    Text("· " + meeting.attendees.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if !meeting.tags.isEmpty {
                HStack {
                    ForEach(meeting.tags, id: \.self) { tag in
                        Text(tag).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            if !meeting.speakers.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "person.wave.2").font(.caption2).foregroundStyle(.secondary)
                    Text(meeting.speakers.map(\.label).joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if !meeting.summary.isEmpty {
                Text(meeting.summary).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            }
            if !meeting.transcript.isEmpty {
                DisclosureGroup(isExpanded: $showTranscript) {
                    ScrollView {
                        Text(meeting.transcript)
                            .font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 240)
                } label: {
                    Text("Full transcript (\(meeting.transcript.count) chars)")
                        .font(.caption).foregroundStyle(.blue)
                }
                .padding(.top, 2)
            }
            HStack {
                Button {
                    appState.startListening(for: meeting)
                } label: {
                    Label("Start & Listen", systemImage: "mic.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isListening)

                Button(role: .destructive) {
                    appState.deleteMeeting(meeting)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

struct MeetingEditor: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var attendees = ""
    @State private var tags = ""
    @State private var startNow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Meeting").font(.title2.bold())
            Form {
                TextField("Title", text: $title)
                TextField("Attendees (comma separated)", text: $attendees)
                TextField("Tags (comma separated)", text: $tags)
                Toggle("Start listening right away", isOn: $startNow)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        let meeting = Meeting(
            title: title,
            attendees: split(attendees),
            tags: split(tags),
            startedAt: Date())
        appState.registerMeeting(meeting)
        if startNow { appState.startListening(for: meeting) }
        dismiss()
    }

    private func split(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
