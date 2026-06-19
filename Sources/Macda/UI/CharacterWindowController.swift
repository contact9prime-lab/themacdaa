import AppKit
import SwiftUI
import Combine

/// Borderless always-on-top panel hosting the mascot/HUD. Sizes itself to the
/// SwiftUI content. Pins to the right edge by default, but remembers where you
/// drag it (anchored by its bottom-right corner so resizing doesn't move it).
@MainActor
final class CharacterWindowController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let appState: AppState
    private let hosting: NSHostingView<CharacterView>
    private var cancellables = Set<AnyCancellable>()
    private var fitWork: DispatchWorkItem?

    private var userAnchor: CGPoint?      // bottom-right corner the user dragged to
    private var programmaticMove = false

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
        super.init()
        panel.delegate = self

        Publishers.MergeMany(
            appState.$isListening.map { _ in () }.eraseToAnyPublisher(),
            appState.$mood.map { _ in () }.eraseToAnyPublisher(),
            appState.$livePreview.map { _ in () }.eraseToAnyPublisher(),
            appState.$partialTranscript.map { _ in () }.eraseToAnyPublisher(),
            appState.$statusLine.map { _ in () }.eraseToAnyPublisher(),
            appState.$showCaptureBubble.map { _ in () }.eraseToAnyPublisher(),
            appState.$artifacts.map { _ in () }.eraseToAnyPublisher(),
            appState.$todos.map { _ in () }.eraseToAnyPublisher(),
            appState.$minimized.map { _ in () }.eraseToAnyPublisher(),
            appState.$settings.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in self?.scheduleFit() }
        .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        fitNow()
    }

    func show() {
        if appState.settings.showMascot { panel.orderFrontRegardless() }
    }

    // MARK: Layout

    @objc private func screenChanged() { clampOnScreen(); fitNow() }

    private func scheduleFit() {
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
        programmaticMove = true
        panel.setContentSize(size)
        positionFor(size: size)
        programmaticMove = false
        panel.orderFrontRegardless()
    }

    /// Keep the bottom-right corner stable (the mascot sits at the bottom), at
    /// the user's dragged spot if any, else the right edge.
    private func positionFor(size: NSSize) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        if let anchor = userAnchor {
            var x = anchor.x - size.width
            var y = anchor.y
            x = min(max(visible.minX, x), visible.maxX - size.width)
            y = min(max(visible.minY, y), visible.maxY - size.height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            let y = appState.minimized ? (visible.minY + 16) : (visible.midY - size.height / 2)
            panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 14, y: y))
        }
    }

    private func clampOnScreen() {
        guard let anchor = userAnchor, let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        userAnchor = CGPoint(x: min(max(v.minX + 40, anchor.x), v.maxX),
                             y: min(max(v.minY, anchor.y), v.maxY - 40))
    }

    // MARK: NSWindowDelegate — track user drags

    func windowDidMove(_ notification: Notification) {
        guard !programmaticMove else { return }
        // Remember where the user put it (by its bottom-right corner).
        userAnchor = CGPoint(x: panel.frame.maxX, y: panel.frame.minY)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
