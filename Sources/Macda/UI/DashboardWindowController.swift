import AppKit
import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case chat, notes, todos, meetings, people, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chat: return "Chat"
        case .notes: return "Notes"
        case .todos: return "To-Dos"
        case .meetings: return "Meetings"
        case .people: return "People"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .notes: return "note.text"
        case .todos: return "checklist"
        case .meetings: return "calendar"
        case .people: return "person.2"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class DashboardWindowController {
    private var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) { self.appState = appState }

    func show() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            win.title = "Macda"
            win.titlebarAppearsTransparent = true
            win.center()
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: DashboardView(appState: appState))
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
