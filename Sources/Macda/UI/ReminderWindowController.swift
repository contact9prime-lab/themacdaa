import AppKit
import SwiftUI

/// A small floating popup that appears when a task's reminder time arrives.
@MainActor
final class ReminderWindowController {
    private var panel: NSPanel?
    private let appState: AppState

    init(appState: AppState) { self.appState = appState }

    func present(_ todo: TodoItem) {
        NSSound(named: "Glass")?.play()
        let view = ReminderPopup(todo: todo, appState: appState) { [weak self] in self?.close() }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 150)

        let p = NSPanel(contentRect: hosting.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.maxX - 340, y: v.maxY - 180))
        }
        p.orderFrontRegardless()
        panel = p
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct ReminderPopup: View {
    let todo: TodoItem
    @ObservedObject var appState: AppState
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill").foregroundStyle(.orange)
                Text("Reminder").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
            }
            Text(todo.title).font(.system(size: 13)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Done") { appState.toggleTodo(todo); onClose() }
                    .buttonStyle(MacdaButtonStyle())
                Button("Snooze 10m") { appState.snoozeTodo(todo, minutes: 10); onClose() }
                    .buttonStyle(MacdaButtonStyle(filled: false))
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .macdaCard(Theme.card, radius: 16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.5), lineWidth: 1))
    }
}
