import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon (works without Accessibility perms):
///   ⌥Space  → start / stop listening
///   ⌥⌘D     → open dashboard
///   ⌥⌘N     → quick note
@MainActor
final class HotKeyManager {
    private let appState: AppState
    private let onToggleListening: () -> Void
    private let onOpenDashboard: () -> Void
    private let onQuickNote: () -> Void
    private let onScreenshot: () -> Void

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    init(appState: AppState,
         onToggleListening: @escaping () -> Void,
         onOpenDashboard: @escaping () -> Void,
         onQuickNote: @escaping () -> Void,
         onScreenshot: @escaping () -> Void) {
        self.appState = appState
        self.onToggleListening = onToggleListening
        self.onOpenDashboard = onOpenDashboard
        self.onQuickNote = onQuickNote
        self.onScreenshot = onScreenshot
    }

    func register() {
        installHandler()
        let optionMod = UInt32(optionKey)
        let cmdOption = UInt32(cmdKey) | optionMod
        add(id: 1, keyCode: UInt32(kVK_Space), modifiers: optionMod, action: onToggleListening)
        add(id: 2, keyCode: UInt32(kVK_ANSI_D), modifiers: cmdOption, action: onOpenDashboard)
        add(id: 3, keyCode: UInt32(kVK_ANSI_N), modifiers: cmdOption, action: onQuickNote)
        add(id: 4, keyCode: UInt32(kVK_ANSI_S), modifiers: cmdOption, action: onScreenshot)
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.fire(id: hkID.id) }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    private func add(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D434441 /* 'MCDA' */), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            handlers[id] = action
            hotKeyRefs.append(ref)
        }
    }

    private func fire(id: UInt32) {
        handlers[id]?()
    }

    deinit {
        for ref in hotKeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
