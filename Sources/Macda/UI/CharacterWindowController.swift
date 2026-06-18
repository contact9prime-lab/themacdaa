import AppKit
import SwiftUI
import Combine

/// Borderless always-on-top panel hosting the mascot/HUD. Sizes itself to the
/// SwiftUI content so the idle mascot has a tiny footprint and the listening
/// HUD expands — staying pinned to the right edge.
@MainActor
final class CharacterWindowController {
    private let panel: NSPanel
    private let appState: AppState
    private let hosting: NSHostingView<CharacterView>
    private var cancellables = Set<AnyCancellable>()
    private var fitWork: DispatchWorkItem?

    init(appState: AppState) {
        self.appState = appState

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        hosting = NSHostingView(rootView: CharacterView(appState: appState))
        panel.contentView = hosting

        // Re-fit whenever something that changes layout changes.
        Publishers.MergeMany(
            appState.$isListening.map { _ in () }.eraseToAnyPublisher(),
            appState.$mood.map { _ in () }.eraseToAnyPublisher(),
            appState.$livePreview.map { _ in () }.eraseToAnyPublisher(),
            appState.$partialTranscript.map { _ in () }.eraseToAnyPublisher(),
            appState.$statusLine.map { _ in () }.eraseToAnyPublisher(),
            appState.$settings.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in self?.scheduleFit() }
        .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(scheduleFit),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        fitNow()
    }

    func show() {
        if appState.settings.showMascot { panel.orderFrontRegardless() }
    }

    @objc private func scheduleFit() {
        fitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fitNow() }
        fitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func fitNow() {
        guard appState.settings.showMascot else { panel.orderOut(nil); return }
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 60 { size.width = 200 }
        if size.height < 60 { size.height = 240 }
        panel.setContentSize(size)
        positionOnRightEdge()
        panel.orderFrontRegardless()
    }

    private func positionOnRightEdge() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 14,
                                     y: visible.midY - size.height / 2))
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
