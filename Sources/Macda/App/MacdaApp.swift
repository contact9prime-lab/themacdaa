import AppKit
import SwiftUI

// Macda — a tiny desk companion that listens during your calls, transcribes
// locally (whisper.cpp) or in the cloud (OpenAI / Gemini), and turns the talk
// into notes + to-dos using your own LLM (Ollama by default).
//
// This is an agent-style app: no Dock icon, lives in the menu bar with a
// floating animated character pinned to the right edge of the screen.

@main
enum MacdaMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Accessory: no Dock icon, no main menu bar app — just menu bar + panel.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
