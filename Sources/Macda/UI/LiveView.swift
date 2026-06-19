import SwiftUI

/// The dark "while it listens" experience: timer, waveform, live transcript.
struct LiveView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            BigWaveform(level: appState.liveLevel, color: Theme.accent)
                .frame(height: 86).padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("LIVE TRANSCRIPT")
                        .font(.system(size: 10, weight: .bold)).tracking(0.6)
                        .foregroundStyle(Theme.darkTextSoft)
                    transcriptBody
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
            }

            Spacer(minLength: 0)

            footer
        }
        .background(Theme.darkBg)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 7, height: 7)
                Text("LISTENING").font(.system(size: 11, weight: .bold)).tracking(0.5)
            }
            .foregroundStyle(Theme.darkText)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Theme.darkCard, in: Capsule())
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(appState.liveElapsedString)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.darkText).monospacedDigit()
            }
        }
        .padding(.horizontal, 22).padding(.top, 18)
    }

    private var transcriptBody: some View {
        let committed = appState.currentTranscript()
        return VStack(alignment: .leading, spacing: 10) {
            if committed.isEmpty && appState.livePreview.isEmpty {
                Text("Listening… start talking and your words appear here.")
                    .font(.system(size: 14)).foregroundStyle(Theme.darkTextSoft)
            }
            if !committed.isEmpty {
                Text(committed).font(.system(size: 15)).foregroundStyle(Theme.darkText)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if !appState.livePreview.isEmpty {
                Text(appState.livePreview).font(.system(size: 15))
                    .foregroundStyle(Theme.darkTextSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if appState.transcribingCount > 0 {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                    Text("transcribing \(appState.transcribingCount)…")
                        .font(.system(size: 11)).foregroundStyle(Theme.darkTextSoft)
                }
            }
            Button { appState.stopListening() } label: {
                Label("Stop & sort this call", systemImage: "stop.fill")
            }
            .buttonStyle(MacdaButtonStyle())
        }
        .padding(18)
    }
}

/// A wide centered audio waveform of bars reacting to the live level.
struct BigWaveform: View {
    var level: Float
    var color: Color
    private let bars = 27

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let center = Double(abs(i - bars / 2)) / Double(bars / 2)
                    let envelope = 1.0 - center * 0.7
                    let wave = abs(sin(t * 6 + Double(i) * 0.5))
                    let h = 6 + wave * envelope * (10 + Double(level) * 120)
                    Capsule().fill(color.opacity(0.65 + envelope * 0.35))
                        .frame(width: 4, height: max(5, h))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
