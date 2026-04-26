import AppKit

/// Watches the modifier-flags state and fires `onPress` / `onRelease` when the
/// user holds the **Right Command key alone** (no other modifiers).
///
/// Implemented via `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`.
/// Carbon's `RegisterEventHotKey` can't handle a modifier-only chord, so we sit
/// at the NSEvent level instead. Requires Accessibility permission (already
/// granted for autopaste).
@MainActor
final class RightCommandMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isHeld = false

    /// Bit positions for device-specific modifier keys, from
    /// IOKit/hidsystem/IOLLEvent.h. Stable values, hardcoded to avoid the
    /// IOKit import noise.
    private struct DeviceMods {
        static let leftCtrl:  UInt = 0x00000001
        static let leftShift: UInt = 0x00000002
        static let rightShift:UInt = 0x00000004
        static let leftCmd:   UInt = 0x00000008
        static let rightCmd:  UInt = 0x00000010
        static let leftAlt:   UInt = 0x00000020
        static let rightAlt:  UInt = 0x00000040
        static let rightCtrl: UInt = 0x00002000

        static let all: UInt = leftCtrl | leftShift | rightShift | leftCmd
            | rightCmd | leftAlt | rightAlt | rightCtrl
    }

    func enable() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        // Also listen to local events — when the user toggles the setting from
        // inside our Settings window, the global monitor doesn't see flagsChanged
        // events delivered to our own app.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func disable() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor = nil }
        if isHeld {
            isHeld = false
            onRelease?()
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.rawValue
        let modifiersDown = flags & DeviceMods.all
        // True only if Right Cmd is the **only** physical modifier currently down.
        // Prevents triggering on Right Cmd + C (copy) etc.
        let onlyRightCmd = modifiersDown == DeviceMods.rightCmd

        if onlyRightCmd && !isHeld {
            isHeld = true
            onPress?()
        } else if !onlyRightCmd && isHeld {
            isHeld = false
            onRelease?()
        }
    }
}
