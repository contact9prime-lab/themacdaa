import AppKit
import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case chat, notes, todos, meetings, people, artifacts, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chat: return "Chat"
        case .notes: return "Notes"
        case .todos: return "To-Dos"
        case .meetings: return "Meetings"
        case .people: return "People"
        case .artifacts: return "Captures"
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
        case .artifacts: return "photo.on.rectangle.angled"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class DashboardWindowController {
    private var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) { self.appState = appState }

    func show(delegate: NSWindowDelegate? = nil) {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            win.title = "Macda"
            win.titlebarAppearsTransparent = true
            win.backgroundColor = NSColor(Theme.cream)
            win.center()
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: DashboardView(appState: appState))
            window = win
        }
        window?.delegate = delegate
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
