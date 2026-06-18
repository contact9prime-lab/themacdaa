import SwiftUI
import AppKit

/// The floating desktop companion. When idle it's just the cute mascot; while
/// listening it expands into a warm HUD card (status, stop, stats, live quote).
struct CharacterView: View {
    @ObservedObject var appState: AppState

    @State private var blink = false
    @State private var breathe = false
    @State private var hovering = false
    private let blinkTimer = Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if appState.isListening {
                expandedHUD
            } else {
                compact
            }
        }
        .frame(width: appState.isListening ? 312 : 168, alignment: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .onReceive(blinkTimer) { _ in doBlink() }
        .onHover { hovering = $0 }
        .contextMenu { ContextMenuContent(appState: appState) }
    }

    // MARK: - Idle / compact

    private var compact: some View {
        VStack(spacing: 8) {
            if hovering || !appState.statusLine.isEmpty {
                Text(appState.statusLine)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: 150)
                    .macdaCard(Theme.card, radius: 12)
                    .opacity(hovering ? 1 : 0.92)
            }
            mascot(size: 116)
                .onTapGesture { appState.toggleListening() }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Listening / HUD

    private var expandedHUD: some View {
        VStack(spacing: 10) {
            statusCard
            if !caughtText.isEmpty { caughtBubble }
            mascot(size: 92).onTapGesture { appState.toggleListening() }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                miniAvatar
                VStack(alignment: .leading, spacing: 1) {
                    Text("Listening…").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("\(appState.activeMeeting?.title ?? "Call") · \(elapsedString)")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                LevelBars(level: appState.liveLevel, color: Theme.accent)
            }

            Button { appState.stopListening() } label: {
                Label("Stop & save notes", systemImage: "stop.fill")
            }
            .buttonStyle(MacdaButtonStyle())

            HStack(spacing: 0) {
                stat("\(appState.meetings.count)", "meetings")
                divider
                stat("\(appState.notes.count)", "notes")
                divider
                stat("\(appState.todos.filter { !$0.done }.count)", "to-dos")
            }

            Divider().overlay(Theme.hairline)

            Toggle(isOn: Binding(get: { appState.settings.autoListen },
                                 set: { appState.setAutoListen($0) })) {
                Text("Auto-listen on speech").font(.system(size: 12)).foregroundStyle(Theme.ink)
            }
            .toggleStyle(.switch).tint(Theme.accent)

            Button { appState.openDashboard?(nil) } label: {
                HStack {
                    Text("Open dashboard").font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text("⌥⌘D").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .macdaCard(Theme.card, radius: 18)
    }

    private var caughtBubble: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("CAUGHT THAT")
                .font(.system(size: 9, weight: .bold)).tracking(0.5)
                .foregroundStyle(Theme.accentDeep)
            Text("“\(caughtText)”")
                .font(.system(size: 12)).foregroundStyle(Theme.ink)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Chip(text: "+ to-do", kind: .accent)
                if appState.transcribingCount > 0 { Chip(text: "transcribing", systemImage: "waveform", kind: .neutral) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macdaCard(Theme.card, radius: 14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accentSoft.opacity(0.6), lineWidth: 1))
    }

    private var caughtText: String {
        let t = [appState.partialTranscript, appState.livePreview]
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(t.suffix(160))
    }

    // MARK: - Pieces

    private var miniAvatar: some View {
        ZStack {
            Circle().fill(Theme.accentSoft)
            Circle().fill(.white).frame(width: 5, height: 5).offset(x: -4)
            Circle().fill(.white).frame(width: 5, height: 5).offset(x: 4)
        }
        .frame(width: 26, height: 26)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.accentDeep)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 26)
    }

    private func mascot(size: CGFloat) -> some View {
        MascotBlob(mood: appState.mood, level: appState.isListening ? appState.liveLevel : 0,
                   blink: blink, breathe: breathe, customHex: appState.settings.mascotColorHex)
            .frame(width: size, height: size)
            .scaleEffect(CGFloat(appState.settings.mascotScale) * (appState.isListening ? 1 : 1.15))
    }

    private var elapsedString: String {
        guard let start = appState.activeMeeting?.startedAt else { return "00:00" }
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func doBlink() {
        blink = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { blink = false }
    }
}

// MARK: - The cute blob

struct MascotBlob: View {
    var mood: MacdaMood
    var level: Float
    var blink: Bool
    var breathe: Bool
    var customHex: String

    private var accent: Color {
        switch mood {
        case .idle: return Color(hex: customHex) ?? Theme.accent
        case .listening: return Color(hex: "C76A41") ?? Theme.accent
        case .thinking: return Color(hex: "CC8A3C") ?? Theme.accent
        case .happy: return Color(hex: "C0603A") ?? Theme.accent
        case .error: return Color(hex: "B5503F") ?? Theme.accent
        }
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if level > 0.02 {
                    Circle().fill(accent.opacity(0.22))
                        .frame(width: s * (1.0 + CGFloat(level)), height: s * (1.0 + CGFloat(level)))
                        .blur(radius: 10)
                }
                // ears
                HStack(spacing: s * 0.34) {
                    ear(s); ear(s)
                }
                .offset(y: -s * 0.42)
                // body
                Circle()
                    .fill(
                        RadialGradient(colors: [accent.opacity(0.95), accent, accent.opacity(0.82)],
                                       center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: s * 0.7)
                    )
                    .overlay(
                        Ellipse().fill(.white.opacity(0.18))
                            .frame(width: s * 0.42, height: s * 0.22)
                            .offset(x: -s * 0.12, y: -s * 0.22).blur(radius: 3)
                    )
                    .frame(width: s * 0.92, height: s * 0.92)
                    .scaleEffect(breathe ? 1.02 : 0.98)
                    .scaleEffect(1 + CGFloat(level) * 0.08)
                    .shadow(color: accent.opacity(0.4), radius: 10, y: 6)
                    .overlay(face(s))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func ear(_ s: CGFloat) -> some View {
        Capsule().fill(accent)
            .frame(width: s * 0.16, height: s * 0.28)
    }

    private func face(_ s: CGFloat) -> some View {
        VStack(spacing: s * 0.09) {
            HStack(spacing: s * 0.18) {
                eye(s); eye(s)
            }
            mouth(s)
        }
        .offset(y: s * 0.04)
    }

    private func eye(_ s: CGFloat) -> some View {
        ZStack {
            Capsule().fill(.white).frame(width: s * 0.15, height: blink ? s * 0.02 : s * 0.18)
            if !blink {
                Circle().fill(Color(hex: "2A1C14") ?? .black)
                    .frame(width: s * 0.075, height: s * 0.075)
                    .offset(y: s * 0.02)
            }
        }
        .animation(.easeInOut(duration: 0.1), value: blink)
    }

    private func mouth(_ s: CGFloat) -> some View {
        Group {
            switch mood {
            case .happy: Smile(open: 0.9).stroke(.white, style: .init(lineWidth: s * 0.03, lineCap: .round)).frame(width: s * 0.3, height: s * 0.14)
            case .error: Smile(open: -0.5).stroke(.white, style: .init(lineWidth: s * 0.03, lineCap: .round)).frame(width: s * 0.26, height: s * 0.1)
            case .listening: Capsule().fill(.white).frame(width: s * 0.12 + CGFloat(level) * s * 0.1, height: s * 0.1 + CGFloat(level) * s * 0.08)
            default: Smile(open: 0.45).stroke(.white, style: .init(lineWidth: s * 0.03, lineCap: .round)).frame(width: s * 0.24, height: s * 0.1)
            }
        }
    }
}

/// Vertical level meter bars.
struct LevelBars: View {
    var level: Float
    var color: Color
    var count = 5
    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<count, id: \.self) { i in
                let phase = sin(Double(i) * 1.3 + Double(level) * 8)
                let h = 6 + CGFloat(max(0, phase)) * CGFloat(level) * 22 + CGFloat(level) * 6
                Capsule().fill(color)
                    .frame(width: 3, height: max(4, h))
                    .animation(.easeOut(duration: 0.12), value: level)
            }
        }
        .frame(height: 28)
    }
}

/// Right-click menu (shared).
struct ContextMenuContent: View {
    @ObservedObject var appState: AppState
    var body: some View {
        Button(appState.isListening ? "Stop Listening" : "Start Listening") { appState.toggleListening() }
        Toggle("Auto-listen (start on speech)", isOn: Binding(
            get: { appState.settings.autoListen }, set: { appState.setAutoListen($0) }))
        Divider()
        Menu("Size") {
            Button("Tiny") { appState.setMascotScale(0.45) }
            Button("Small") { appState.setMascotScale(0.62) }
            Button("Medium") { appState.setMascotScale(0.85) }
            Button("Large") { appState.setMascotScale(1.1) }
        }
        Menu("Color") {
            ForEach(Color.mascotPresets, id: \.hex) { p in
                Button(p.name) { appState.setMascotColor(p.hex) }
            }
        }
        Button("Hide mascot") { appState.setShowMascot(false) }
        Divider()
        Button("Capture Screen (⌥⌘S)") { appState.captureScreenshot() }
        Button("Chat…") { appState.openDashboard?(.chat) }
        Button("Notes…") { appState.openDashboard?(.notes) }
        Button("Meetings…") { appState.openDashboard?(.meetings) }
        Button("People…") { appState.openDashboard?(.people) }
        Button("Settings…") { appState.openDashboard?(.settings) }
        Divider()
        Button("Quit Macda") { NSApp.terminate(nil) }
    }
}

/// A simple smile/frown arc.
struct Smile: Shape {
    var open: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                       control: CGPoint(x: rect.midX, y: rect.midY + open * rect.height))
        return p
    }
}
