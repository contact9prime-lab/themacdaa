import AppKit
import Combine

/// Always-visible menu bar item: shows a live recording indicator, lets you
/// bring back a hidden mascot, toggle listening, and open the dashboard.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private let onOpenDashboard: () -> Void
    private let onQuit: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, onOpenDashboard: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.appState = appState
        self.onOpenDashboard = onOpenDashboard
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        buildMenu()

        appState.$mood.sink { [weak self] _ in self?.configureButton() }.store(in: &cancellables)
        appState.$isListening.sink { [weak self] _ in
            self?.configureButton(); self?.buildMenu()
        }.store(in: &cancellables)
        // The per-second tick reliably refreshes the menu-bar timer while recording.
        appState.$liveTick.sink { [weak self] _ in self?.configureButton() }.store(in: &cancellables)
        appState.$settings.sink { [weak self] _ in self?.buildMenu() }.store(in: &cancellables)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if appState.isListening {
            // Clear "recording" indicator with a live timer — visible even when
            // the mascot is hidden.
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: "🔴 \(appState.liveElapsedString)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)])
            return
        }
        button.attributedTitle = NSAttributedString(string: "")
        let symbol: String
        switch appState.mood {
        case .idle: symbol = "face.smiling"
        case .listening: symbol = "waveform.circle.fill"
        case .thinking: symbol = "ellipsis.circle"
        case .happy: symbol = "checkmark.circle.fill"
        case .error: symbol = "exclamationmark.triangle.fill"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Macda")
        button.image?.isTemplate = true
    }

    private func buildMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(title: appState.isListening ? "Stop Listening" : "Start Listening",
                                action: #selector(toggleListening), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let dashboard = NSMenuItem(title: "Open Dashboard…", action: #selector(openDashboard), keyEquivalent: "d")
        dashboard.target = self
        menu.addItem(dashboard)

        menu.addItem(.separator())

        // Recover a hidden mascot (this is the only way back once it's hidden).
        let mascot = NSMenuItem(title: appState.settings.showMascot ? "Hide Mascot" : "Show Mascot",
                                action: #selector(toggleMascot), keyEquivalent: "")
        mascot.target = self
        menu.addItem(mascot)

        menu.addItem(.separator())

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Macda", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private var statusTitle: String {
        if appState.isListening { return "🎙 Listening · \(appState.liveElapsedString)" }
        return appState.settings.showMascot ? "💤 Idle — ⌥Space to start" : "💤 Mascot hidden — ⌥Space to start"
    }

    @objc private func toggleListening() { appState.toggleListening() }
    @objc private func openDashboard() { onOpenDashboard() }
    @objc private func toggleMascot() { appState.setShowMascot(!appState.settings.showMascot) }
    @objc private func quit() { onQuit() }
}
