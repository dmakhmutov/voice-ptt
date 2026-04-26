import AppKit
import Carbon.HIToolbox

enum Paster {
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKeyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        vKeyDown?.flags = .maskCommand
        let vKeyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        vKeyUp?.flags = .maskCommand
        vKeyDown?.post(tap: .cghidEventTap)
        vKeyUp?.post(tap: .cghidEventTap)

        if let saved {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let current = pb.string(forType: .string)
                if current == text {
                    pb.clearContents()
                    pb.setString(saved, forType: .string)
                }
            }
        }
    }
}
