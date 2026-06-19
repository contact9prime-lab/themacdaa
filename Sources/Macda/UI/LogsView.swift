import SwiftUI
import AppKit

/// Tails the Macda log file inside the dashboard, refreshing like `tail -f`.
struct LogsView: View {
    @StateObject private var tailer = LogTailer()
    @State private var follow = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                header("Logs", subtitle: "Live tail of macda.log — events, errors, and crashes.")
                Spacer()
                HStack(spacing: 8) {
                    Toggle("Follow", isOn: $follow).toggleStyle(.switch).tint(Theme.accent)
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL]) }
                    Button("Clear") { tailer.clear() }
                }
                .padding(.trailing).padding(.top)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(tailer.text.isEmpty ? "(no log output yet)" : tailer.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("logbottom")
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
                .onChange(of: tailer.text) { _, _ in
                    if follow { withAnimation { proxy.scrollTo("logbottom", anchor: .bottom) } }
                }
            }
        }
        .onAppear { tailer.start() }
        .onDisappear { tailer.stop() }
    }
}

@MainActor
final class LogTailer: ObservableObject {
    @Published var text = ""
    private var timer: Timer?

    func start() {
        load()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func clear() {
        try? "".data(using: .utf8)?.write(to: Log.fileURL)
        text = ""
        Log.info("Log cleared from dashboard")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Log.fileURL),
              let full = String(data: data, encoding: .utf8) else { return }
        // Keep the last ~400 lines so the view stays snappy.
        let lines = full.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(400).joined(separator: "\n")
        if tail != text { text = tail }
    }
}
