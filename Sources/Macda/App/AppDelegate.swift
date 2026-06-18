import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appState = AppState()

    private var menuBar: MenuBarController!
    private var characterWindow: CharacterWindowController!
    private var hotKeys: HotKeyManager!
    private var dashboard: DashboardWindowController!
    private var liveWindow: LiveWindowController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Even as a menu-bar app, install a main menu so the standard editing
        // shortcuts (⌘C/⌘V/⌘X/⌘A/⌘Z) work in the dashboard's text fields.
        installMainMenu()

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
                                onQuickNote: { [weak self] in self?.openDashboard(tab: .notes) },
                                onScreenshot: { [weak self] in self?.appState.captureScreenshot() })
        hotKeys.register()

        // Dark "live" window appears while listening.
        liveWindow = LiveWindowController(appState: appState)
        appState.$isListening
            .removeDuplicates()
            .sink { [weak self] listening in
                if listening { self?.liveWindow.show() } else { self?.liveWindow.hide() }
            }
            .store(in: &cancellables)

        appState.bootstrap()
    }

    /// Full menu bar: Macda / Edit / View (tab switching) / Window.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // Macda (app) menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Macda", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let listen = appMenu.addItem(withTitle: "Start / Stop Listening", action: #selector(menuToggleListening), keyEquivalent: "")
        listen.target = self
        let cap = appMenu.addItem(withTitle: "Capture Screen", action: #selector(menuCaptureScreen), keyEquivalent: "s")
        cap.keyEquivalentModifierMask = [.command, .option]; cap.target = self
        appMenu.addItem(.separator())
        let dash = appMenu.addItem(withTitle: "Open Dashboard", action: #selector(menuOpenDashboard), keyEquivalent: "d")
        dash.keyEquivalentModifierMask = [.command, .option]; dash.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Macda", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Macda", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu — copy/paste/cut/select-all/undo.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View menu — switch dashboard tabs with ⌘1…⌘7.
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        for (i, tab) in DashboardTab.allCases.enumerated() {
            let item = viewMenu.addItem(withTitle: tab.title, action: #selector(menuSwitchTab(_:)), keyEquivalent: "\(i + 1)")
            item.tag = i
            item.target = self
        }

        // Window menu.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func openDashboard(tab: DashboardTab? = nil) {
        if let tab { appState.selectedTab = tab }
        // Become a regular app so the top menu bar + Cmd-Tab work while the
        // dashboard is open.
        NSApp.setActivationPolicy(.regular)
        dashboard.show(delegate: self)
        NSApp.activate(ignoringOtherApps: true)
    }

    // When the dashboard closes, drop back to a menu-bar-only accessory app.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let hasVisibleDashboard = NSApp.windows.contains {
                $0.isVisible && $0.delegate === self && !($0 == notification.object as? NSWindow)
            }
            if !hasVisibleDashboard { NSApp.setActivationPolicy(.accessory) }
        }
    }

    // MARK: - Menu actions

    @objc private func menuToggleListening() { appState.toggleListening() }
    @objc private func menuCaptureScreen() { appState.captureScreenshot() }
    @objc private func menuOpenDashboard() { openDashboard() }
    @objc private func menuSwitchTab(_ sender: NSMenuItem) {
        let tabs = DashboardTab.allCases
        guard sender.tag >= 0, sender.tag < tabs.count else { return }
        openDashboard(tab: tabs[sender.tag])
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.shutdown()
    }
}
