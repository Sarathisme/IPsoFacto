import Carbon.HIToolbox
import AppKit

/// A key + modifier combination the user can configure to trigger Copy
/// IP Address globally. `keyCode` is a Carbon virtual key code (from the
/// table below); `modifierFlags` is a Carbon modifier bitmask (cmdKey /
/// optionKey / controlKey / shiftKey), NOT NSEvent.ModifierFlags' raw
/// value -- the two use different bit positions (Decision #11).
struct GlobalHotKey: Equatable {
    let keyCode: UInt32
    let modifierFlags: UInt32

    /// A-Z and 0-9 only (Decision #11), keyed by Carbon virtual key code,
    /// as read from this machine's Carbon.framework headers.
    static let keyCodeDisplayNames: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
        35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
        13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9"
    ]

    /// Human-readable form for display in Preferences, e.g. "⌃⌥I".
    var displayString: String {
        var result = ""
        if modifierFlags & UInt32(controlKey) != 0 { result += "⌃" }
        if modifierFlags & UInt32(optionKey) != 0 { result += "⌥" }
        if modifierFlags & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifierFlags & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyCodeDisplayNames[keyCode] ?? "?"
        return result
    }

    /// Converts an NSEvent's modifier flags (as seen by the Preferences
    /// recorder) to the Carbon bitmask RegisterEventHotKey expects.
    /// Only command/option/control/shift are considered.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

/// Registers and unregisters a single system-wide hotkey via Carbon's
/// RegisterEventHotKey -- the same mechanism used by third-party hotkey
/// libraries (e.g. HotKey, KeyHolder). Requires no Accessibility/Input
/// Monitoring permission, unlike a CGEventTap or a global NSEvent
/// monitor. Only one hotkey is ever registered at a time; re-registering
/// replaces the previous one.
@MainActor
final class GlobalHotKeyManager {
    /// Called on the main thread when the registered hotkey fires.
    var onHotKeyPressed: (() -> Void)?

    // These are only ever mutated from main-actor-isolated methods
    // (`register`/`unregister`/`installEventHandler`); `deinit` runs only
    // once no more references exist, so there is no concurrent access --
    // `nonisolated(unsafe)` lets `deinit` (which is not actor-isolated)
    // clean them up without the compiler flagging the raw C pointer types
    // as non-Sendable.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4950464F // 'IPFO'
    private static let hotKeyID = EventHotKeyID(signature: signature, id: 1)

    init() {
        installEventHandler()
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    /// Unregisters any existing hotkey, then registers `hotKey`.
    /// Silently does nothing further if registration fails (e.g. the
    /// combo is already claimed system-wide) -- Decision #12.
    func register(_ hotKey: GlobalHotKey) {
        unregister()
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifierFlags, Self.hotKeyID, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr else { return }
        hotKeyRef = newRef
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var receivedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &receivedID)
            guard receivedID.id == GlobalHotKeyManager.hotKeyID.id else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in manager.onHotKeyPressed?() }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandlerRef)
    }
}
