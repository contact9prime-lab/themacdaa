import AppKit
import SwiftUI
import Combine

/// A borderless, always-on-top panel that hosts the mascot and pins itself to
/// the right edge. Resizes with the user's chosen scale and can be hidden.
@MainActor
final class CharacterWindowController {
    private let panel: NSPanel
    private let appState: AppState
    private let baseSize = NSSize(width: 200, height: 240)
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState

        panel = NSPanel(contentRect: NSRect(origin: .zero, size: baseSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hosting = NSHostingView(rootView: CharacterView(appState: appState))
        panel.contentView = hosting

        applyAppearance()

        NotificationCenter.default.addObserver(
            self, selector: #selector(reanchor),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // React to size / visibility changes from Settings or the quick menu.
        appState.$settings
            .map { ($0.mascotScale, $0.showMascot) }
            .removeDuplicates(by: { $0 == $1 })
            .sink { [weak self] _ in self?.applyAppearance() }
            .store(in: &cancellables)
    }

    func show() {
        if appState.settings.showMascot { panel.orderFrontRegardless() }
    }

    private func applyAppearance() {
        guard appState.settings.showMascot else { panel.orderOut(nil); return }
        let scale = CGFloat(appState.settings.mascotScale)
        let size = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
        panel.setContentSize(size)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        positionOnRightEdge()
        panel.orderFrontRegardless()
    }

    @objc private func reanchor() {
        positionOnRightEdge()
        if appState.settings.showMascot { panel.orderFrontRegardless() }
    }

    private func positionOnRightEdge() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 12,
                                     y: visible.midY - size.height / 2))
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
