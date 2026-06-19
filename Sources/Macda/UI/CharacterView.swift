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

    private var isMinimized: Bool { appState.minimized && !hovering && !appState.isListening }

    var body: some View {
        Group {
            if isMinimized {
                minimizedView
            } else if appState.isListening {
                expandedHUD
            } else {
                compact
            }
        }
        .frame(width: bodyWidth, alignment: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .onReceive(blinkTimer) { _ in doBlink() }
        .onHover { h in hovering = h; if h { appState.wakeMascot() } }
        .contextMenu { ContextMenuContent(appState: appState) }
    }

    private var bodyWidth: CGFloat {
        if isMinimized { return 60 }
        if appState.isListening { return 248 }
        return (appState.showCaptureBubble || !appState.overdueTodos.isEmpty) ? 240 : 150
    }

    /// Tiny idle dock — just the buddy, small.
    private var minimizedView: some View {
        mascot(size: 44)
            .onTapGesture { appState.wakeMascot() }
            .padding(.bottom, 2)
    }

    // MARK: - Idle / compact

    private var compact: some View {
        VStack(spacing: 8) {
            if !appState.overdueTodos.isEmpty { reminderBubble }
            if appState.showCaptureBubble { captureBubble }
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

    /// Nudges about overdue tasks — click to jump to To-Dos.
    private var reminderBubble: some View {
        Button { appState.openDashboard?(.todos) } label: {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(appState.overdueTodos.count) task\(appState.overdueTodos.count == 1 ? "" : "s") overdue")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink)
                    if let first = appState.overdueTodos.first {
                        Text(first.title).font(.system(size: 10)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: 220, alignment: .leading)
            .macdaCard(Theme.card, radius: 12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Shows the latest screen capture (thumbnail + AI analysis) in the bubble.
    private var captureBubble: some View {
        let art = appState.artifacts.first
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "camera.fill").font(.system(size: 9))
                Text("SCREEN CAPTURE").font(.system(size: 8, weight: .bold)).tracking(0.5)
            }
            .foregroundStyle(Theme.accentDeep)
            if let art, let img = NSImage(contentsOfFile: art.imagePath) {
                Image(nsImage: img).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(maxHeight: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
            }
            if let art {
                if art.analyzing {
                    HStack(spacing: 5) { ProgressView().controlSize(.small); Text("Analyzing…").font(.system(size: 10)).foregroundStyle(Theme.inkSoft) }
                } else if !art.aiText.isEmpty {
                    Text(art.aiText).font(.system(size: 10)).foregroundStyle(Theme.ink)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: 220, alignment: .leading)
        .macdaCard(Theme.card, radius: 12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accentSoft.opacity(0.6), lineWidth: 1))
    }

    // MARK: - Listening / HUD

    private var expandedHUD: some View {
        VStack(spacing: 8) {
            statusCard
            if appState.showCaptureBubble { captureBubble }
            if !caughtText.isEmpty { caughtBubble }
            mascot(size: 58).onTapGesture { appState.toggleListening() }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                miniAvatar
                VStack(alignment: .leading, spacing: 0) {
                    Text("Listening…").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.ink)
                    // TimelineView so the timer ticks even during silence (when the
                    // view wouldn't otherwise re-render) — keeps it in sync with the menu bar.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(appState.activeMeeting?.title ?? "Call") · \(appState.liveElapsedString)")
                            .font(.system(size: 10)).foregroundStyle(Theme.inkSoft)
                    }
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

            Button { appState.openDashboard?(nil) } label: {
                HStack {
                    Text("Open dashboard").font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text("⌥⌘D").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .macdaCard(Theme.card, radius: 16)
    }

    private var caughtBubble: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CAUGHT THAT")
                .font(.system(size: 8, weight: .bold)).tracking(0.5)
                .foregroundStyle(Theme.accentDeep)
            Text("“\(caughtText)”")
                .font(.system(size: 11)).foregroundStyle(Theme.ink)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if appState.transcribingCount > 0 {
                Chip(text: "transcribing \(appState.transcribingCount)", systemImage: "waveform", kind: .neutral)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macdaCard(Theme.card, radius: 12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accentSoft.opacity(0.6), lineWidth: 1))
    }

    private var caughtText: String {
        let t = [appState.partialTranscript, appState.livePreview]
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(t.suffix(120))
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
        VStack(spacing: 0) {
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accentDeep)
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 22)
    }

    private func mascot(size: CGFloat) -> some View {
        MascotBlob(mood: appState.mood, level: appState.isListening ? appState.liveLevel : 0,
                   blink: blink, breathe: breathe, customHex: appState.settings.mascotColorHex,
                   style: appState.settings.mascotStyle)
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
    var style: String = "bear"

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
                // ears / antenna (varies by avatar style)
                if style == "robot" {
                    VStack(spacing: 0) {
                        Circle().fill(accent).frame(width: s * 0.12, height: s * 0.12)
                        Rectangle().fill(accent).frame(width: s * 0.035, height: s * 0.16)
                    }
                    .offset(y: -s * 0.54)
                } else {
                    HStack(spacing: earSpacing * s) {
                        earShape(s)
                        earShape(s).scaleEffect(x: -1)
                    }
                    .offset(y: earOffset * s)
                }
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

    private var earSpacing: CGFloat { style == "bunny" ? 0.30 : 0.34 }
    private var earOffset: CGFloat {
        switch style {
        case "bunny": return -0.56
        case "cat", "fox": return -0.46
        default: return -0.42
        }
    }

    @ViewBuilder
    private func earShape(_ s: CGFloat) -> some View {
        switch style {
        case "cat", "fox":
            Triangle().fill(accent).frame(width: s * 0.22, height: s * 0.26)
        case "bunny":
            Capsule().fill(accent).frame(width: s * 0.13, height: s * 0.4)
        default: // bear — round ears
            Circle().fill(accent).frame(width: s * 0.24, height: s * 0.24)
        }
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
        Toggle("Talking mode (speak replies)", isOn: Binding(
            get: { appState.settings.talkBack }, set: { appState.setTalkBack($0) }))
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
        Menu("Buddy") {
            ForEach(mascotStyles, id: \.id) { s in
                Button(s.name) { appState.setMascotStyle(s.id) }
            }
        }
        Button("Hide mascot") { appState.setShowMascot(false) }
        Divider()
        Button("Capture Screen (⌥⌘S)") { appState.captureScreenshot() }
        if appState.isListening { Button("Open Live View…") { appState.openLiveView?() } }
        Button("Chat…") { appState.openDashboard?(.chat) }
        Button("Notes…") { appState.openDashboard?(.notes) }
        Button("Meetings…") { appState.openDashboard?(.meetings) }
        Button("People…") { appState.openDashboard?(.people) }
        Button("Settings…") { appState.openDashboard?(.settings) }
        Divider()
        Button("Quit Macda") { NSApp.terminate(nil) }
    }
}

/// A triangle pointing up (cat/fox ears).
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
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
