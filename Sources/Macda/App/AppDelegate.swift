import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var menuBar: MenuBarController!
    private var characterWindow: CharacterWindowController!
    private var hotKeys: HotKeyManager!
    private var dashboard: DashboardWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Floating mascot pinned to the right edge.
        characterWindow = CharacterWindowController(appState: appState)
        characterWindow.show()

        // Menu bar item with quick controls.
        menuBar = MenuBarController(appState: appState,
                                    onOpenDashboard: { [weak self] in self?.openDashboard() },
                                    onQuit: { NSApp.terminate(nil) })

        // Dashboard window (chat / notes / todos / meetings / people / settings).
        dashboard = DashboardWindowController(appState: appState)
        appState.openDashboard = { [weak self] tab in self?.openDashboard(tab: tab) }

        // Global shortcuts.
        hotKeys = HotKeyManager(appState: appState,
                                onToggleListening: { [weak self] in self?.appState.toggleListening() },
                                onOpenDashboard: { [weak self] in self?.openDashboard() },
                                onQuickNote: { [weak self] in self?.openDashboard(tab: .notes) })
        hotKeys.register()

        appState.bootstrap()
    }

    private func openDashboard(tab: DashboardTab? = nil) {
        if let tab { appState.selectedTab = tab }
        dashboard.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.shutdown()
    }
}
