import Carbon.HIToolbox
import Foundation

final class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private static let hotKeyID = EventHotKeyID(signature: OSType(0x56505454), id: 1) // 'VPTT'

    init() {
        installHandler()
    }

    deinit {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ binding: HotkeyBinding) {
        unregister()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("VoicePTT: RegisterEventHotKey failed with status \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandler() {
        var spec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(event)
                DispatchQueue.main.async {
                    if kind == UInt32(kEventHotKeyPressed) {
                        manager.onKeyDown?()
                    } else if kind == UInt32(kEventHotKeyReleased) {
                        manager.onKeyUp?()
                    }
                }
                return noErr
            },
            spec.count,
            &spec,
            userData,
            &eventHandler
        )
    }
}
