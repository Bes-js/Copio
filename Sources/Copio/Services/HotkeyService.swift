import AppKit
import Carbon

@MainActor final class HotkeyService {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { service.onPress?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(keyCode: Int, modifiers: Int) -> Bool {
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        let identifier = EventHotKeyID(signature: OSType(0x43636C70), id: 1)
        return RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), identifier, GetApplicationEventTarget(), 0, &hotkey) == noErr
    }
}
