import SwiftUI

struct MeetingsView: View {
    @ObservedObject var appState: AppState
    @State private var showingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                header("Meetings", subtitle: "Everything Macda sat in on. Tap one to reopen the transcript.")
                Spacer()
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .padding(8).background(Theme.chipAccentBg, in: Circle())
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.trailing).padding(.top)
            }

            if appState.meetings.isEmpty {
                emptyState("No meetings yet", "Tap + to register one, or just Start listening.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.meetings) { meeting in
                            MeetingRow(meeting: meeting, appState: appState)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingNew) { MeetingEditor(appState: appState) }
    }
}

struct MeetingRow: View {
    let meeting: Meeting
    @ObservedObject var appState: AppState
    @ObservedObject private var playback = AudioPlayback.shared
    @State private var showTranscript = false

    private var availableAudio: [String] {
        meeting.audioFiles.filter { FileManager.default.fileExists(atPath: $0) }
    }

    private var isLive: Bool { appState.activeMeeting?.id == meeting.id && appState.isListening }
    private var todoCount: Int { appState.todos.filter { $0.meetingID == meeting.id }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if isLive {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.chipGreenInk).frame(width: 7, height: 7)
                        Text("LIVE").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.chipGreenInk)
                    }
                }
                Text(meeting.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(isLive ? elapsed : "\(relativeDay) · \(meeting.durationString)")
                    .font(.system(size: 12, weight: isLive ? .semibold : .regular))
                    .foregroundStyle(isLive ? Theme.accentDeep : Theme.inkSoft)
            }

            if isLive {
                HStack(spacing: 6) {
                    Text("Speakers").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    Chip(text: "You", kind: .green)
                    ForEach(meeting.attendees.prefix(3), id: \.self) { Chip(text: $0, kind: .green) }
                    Chip(text: "+ new voice", kind: .neutral)
                }
            } else {
                if !meeting.summary.isEmpty {
                    Text(meeting.summary).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !meeting.speakers.isEmpty || todoCount > 0 || !meeting.tags.isEmpty {
                    HStack(spacing: 6) {
                        if todoCount > 0 { Chip(text: "\(todoCount) to-do\(todoCount == 1 ? "" : "s")", kind: .accent) }
                        if !meeting.speakers.isEmpty {
                            Chip(text: meeting.speakers.map(\.label).prefix(3).joined(separator: " · "), kind: .green)
                        } else if !meeting.attendees.isEmpty {
                            Chip(text: meeting.attendees.prefix(3).joined(separator: " · "), kind: .green)
                        }
                        ForEach(meeting.tags.prefix(2), id: \.self) { Chip(text: "#\($0)", kind: .neutral) }
                    }
                }
            }

            if !meeting.transcript.isEmpty {
                DisclosureGroup(isExpanded: $showTranscript) {
                    ScrollView {
                        Text(meeting.transcript).font(.system(size: 12)).foregroundStyle(Theme.ink)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 220)
                } label: {
                    Text("Transcript").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accentDeep)
                }
                .tint(Theme.accentDeep)
            }

            if !isLive {
                HStack(spacing: 8) {
                    if !availableAudio.isEmpty {
                        Button { playback.playSequence(availableAudio, id: meeting.id.uuidString) } label: {
                            Label(playback.playingPath == meeting.id.uuidString ? "Stop" : "Play recording",
                                  systemImage: playback.playingPath == meeting.id.uuidString ? "stop.fill" : "play.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    if !meeting.transcript.isEmpty {
                        Button { appState.reprocessMeeting(meeting) } label: {
                            Label("Re-generate notes", systemImage: "arrow.clockwise").font(.system(size: 11))
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(Theme.accent)
                    }
                    Spacer()
                    Button(role: .destructive) { appState.deleteMeeting(meeting) } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(14)
        .macdaCard(isLive ? Theme.liveHighlight : Theme.card, radius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(isLive ? Theme.accentSoft : .clear, lineWidth: 1.5)
        )
    }

    private var elapsed: String {
        let s = max(0, Int(Date().timeIntervalSince(meeting.startedAt)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
    private var relativeDay: String {
        Calendar.current.isDateInToday(meeting.startedAt) ? "Today"
            : Calendar.current.isDateInYesterday(meeting.startedAt) ? "Yesterday"
            : meeting.startedAt.formatted(.dateTime.weekday(.abbreviated))
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
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(title.isEmpty)
            }
        }
        .padding(20).frame(width: 420)
    }

    private func save() {
        let meeting = Meeting(title: title, attendees: split(attendees), tags: split(tags), startedAt: Date())
        appState.registerMeeting(meeting)
        if startNow { appState.startListening(for: meeting) }
        dismiss()
    }
    private func split(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
