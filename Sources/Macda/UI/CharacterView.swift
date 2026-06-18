import SwiftUI
import AppKit

/// Macda the mascot — a little blob that blinks, breathes, perks its ears up
/// while listening, and reacts to your voice level. Click it to start/stop.
struct CharacterView: View {
    @ObservedObject var appState: AppState

    @State private var blink = false
    @State private var breathe = false
    @State private var wave = false
    @State private var spin = false
    @State private var bubbleHover = false

    private let blinkTimer = Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            speechBubble
                .opacity(showBubble ? 1 : 0)
                .scaleEffect(showBubble ? 1 : 0.85, anchor: .bottom)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showBubble)

            character
                .onTapGesture { appState.toggleListening() }
                .onHover { bubbleHover = $0 }
                .contextMenu { contextMenu }
        }
        .frame(width: 200, height: 240, alignment: .bottom)
        .scaleEffect(scale, anchor: .bottom)
        .frame(width: 200 * scale, height: 240 * scale, alignment: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { wave = true }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        }
        .onReceive(blinkTimer) { _ in doBlink() }
    }

    // MARK: Right-click menu

    @ViewBuilder
    private var contextMenu: some View {
        Button(appState.isListening ? "Stop Listening" : "Start Listening") {
            appState.toggleListening()
        }
        Toggle("Auto-listen (start on speech)", isOn: Binding(
            get: { appState.settings.autoListen },
            set: { appState.setAutoListen($0) }))
        Divider()
        Menu("Size") {
            Button("Tiny") { appState.setMascotScale(0.45) }
            Button("Small") { appState.setMascotScale(0.62) }
            Button("Medium") { appState.setMascotScale(0.85) }
            Button("Large") { appState.setMascotScale(1.1) }
        }
        Menu("Color") {
            ForEach(Color.mascotPresets, id: \.hex) { preset in
                Button(preset.name) { appState.setMascotColor(preset.hex) }
            }
        }
        Button("Hide mascot") { appState.setShowMascot(false) }
        Divider()
        Button("Chat…") { appState.openDashboard?(.chat) }
        Button("Notes…") { appState.openDashboard?(.notes) }
        Button("To-Dos…") { appState.openDashboard?(.todos) }
        Button("Meetings…") { appState.openDashboard?(.meetings) }
        Button("People…") { appState.openDashboard?(.people) }
        Button("Settings…") { appState.openDashboard?(.settings) }
        Divider()
        Button("Quit Macda") { NSApp.terminate(nil) }
    }

    // MARK: Character body

    private var character: some View {
        ZStack {
            // Audio-reactive glow while listening.
            if appState.isListening {
                Circle()
                    .fill(accent.opacity(0.25))
                    .frame(width: 120 + CGFloat(appState.liveLevel) * 90,
                           height: 120 + CGFloat(appState.liveLevel) * 90)
                    .blur(radius: 14)
                    .animation(.easeOut(duration: 0.15), value: appState.liveLevel)
            }

            // Ears (perk up when listening).
            HStack(spacing: 58) {
                ear.rotationEffect(.degrees(earAngle), anchor: .bottom)
                ear.scaleEffect(x: -1).rotationEffect(.degrees(-earAngle), anchor: .bottom)
            }
            .offset(y: -52)

            // Body blob.
            blobBody
                .frame(width: 110, height: 96)
                .scaleEffect(breathe ? 1.03 : 0.97)
                .scaleEffect(1 + CGFloat(appState.liveLevel) * 0.12)
                .overlay(face)
                .shadow(color: accent.opacity(0.35), radius: 12, y: 6)

            if case .thinking = appState.mood { thinkingDots.offset(y: -64) }
            if case .happy = appState.mood { sparkles }
            if appState.transcribingCount > 0 { workingBadge.offset(y: -74) }
        }
        .frame(width: 160, height: 150)
        .offset(y: wave ? -3 : 3)
    }

    private var blobBody: some View {
        RoundedRectangle(cornerRadius: 48, style: .continuous)
            .fill(
                LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
            )
    }

    private var ear: some View {
        Capsule()
            .fill(accent.opacity(0.85))
            .frame(width: 18, height: 34)
    }

    private var face: some View {
        VStack(spacing: 10) {
            HStack(spacing: 22) {
                eye
                eye
            }
            mouth
        }
        .offset(y: 4)
    }

    private var eye: some View {
        ZStack {
            Capsule()
                .fill(.white)
                .frame(width: 16, height: blink ? 2 : 20)
            if !blink {
                Circle()
                    .fill(.black)
                    .frame(width: 8, height: 8)
                    .offset(x: pupilOffset, y: 3)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: blink)
        .animation(.easeOut(duration: 0.2), value: pupilOffset)
    }

    private var mouth: some View {
        Group {
            switch appState.mood {
            case .happy:
                Smile(open: 0.8).stroke(.white, lineWidth: 3).frame(width: 34, height: 16)
            case .error:
                Smile(open: -0.5).stroke(.white, lineWidth: 3).frame(width: 30, height: 12)
            case .listening:
                Circle().fill(.white).frame(width: 12 + CGFloat(appState.liveLevel) * 16,
                                            height: 10 + CGFloat(appState.liveLevel) * 14)
            default:
                Smile(open: 0.3).stroke(.white, lineWidth: 3).frame(width: 28, height: 12)
            }
        }
    }

    /// Shown while chunks are being sent for transcription in the background.
    private var workingBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .rotationEffect(.degrees(spin ? 360 : 0))
            Text("transcribing\(appState.transcribingCount > 1 ? " ×\(appState.transcribingCount)" : "")")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(accent.opacity(0.9)))
        .shadow(radius: 3)
        .transition(.scale.combined(with: .opacity))
    }

    private var thinkingDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(accent)
                    .frame(width: 7, height: 7)
                    .scaleEffect(wave ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: wave)
            }
        }
        .padding(7)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var sparkles: some View {
        ForEach(0..<5) { i in
            Image(systemName: "sparkle")
                .foregroundStyle(.yellow)
                .font(.system(size: CGFloat(8 + i * 2)))
                .offset(x: [-50, 40, -30, 48, 0][i], y: [-40, -30, 30, 20, -60][i])
                .opacity(wave ? 1 : 0.2)
        }
    }

    // MARK: Speech bubble

    private var speechBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appState.statusLine)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            if !appState.partialTranscript.isEmpty {
                Text(appState.partialTranscript)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 190, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.3), lineWidth: 1))
    }

    // MARK: Derived

    private var showBubble: Bool {
        bubbleHover || appState.isListening || !appState.partialTranscript.isEmpty
            || isErrorMood
    }

    private var isErrorMood: Bool {
        if case .error = appState.mood { return true }
        return false
    }

    private var earAngle: Double {
        appState.isListening ? 8 : 24
    }

    private var pupilOffset: CGFloat {
        // Eyes drift toward the screen centre (left) while listening.
        appState.isListening ? -2 : 0
    }

    private var scale: CGFloat { CGFloat(appState.settings.mascotScale) }

    private var accent: Color {
        // Mood colors stay semantic; idle uses the user's chosen tint.
        switch appState.mood {
        case .idle:
            return Color(hex: appState.settings.mascotColorHex) ?? Color(red: 0.45, green: 0.55, blue: 0.95)
        case .listening: return Color(red: 0.30, green: 0.78, blue: 0.55)
        case .thinking: return Color(red: 0.95, green: 0.70, blue: 0.30)
        case .happy: return Color(red: 0.55, green: 0.45, blue: 0.95)
        case .error: return Color(red: 0.90, green: 0.40, blue: 0.45)
        }
    }

    private func doBlink() {
        blink = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { blink = false }
    }
}

/// A simple smile/frown arc. `open` > 0 smiles, < 0 frowns.
struct Smile: Shape {
    var open: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midX
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                       control: CGPoint(x: mid, y: rect.midY + open * rect.height))
        return p
    }
}
