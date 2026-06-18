import AppKit
import SwiftUI

@MainActor
final class LiveWindowController {
    private var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) { self.appState = appState }

    func show() {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            win.title = "Macda — Live"
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = true
            win.backgroundColor = NSColor(Theme.darkBg)
            win.isReleasedWhenClosed = false
            win.contentView = NSHostingView(rootView: LiveView(appState: appState))
            win.center()
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}
