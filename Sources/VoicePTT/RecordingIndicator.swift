import AppKit

/// A small floating dot near the mouse cursor while recording is active.
/// macOS doesn't let menubar apps change the system cursor (NSCursor only
/// affects the cursor while our app is frontmost), so we follow the cursor
/// with a tiny non-activating panel instead.
@MainActor
final class RecordingIndicator {
    private var panel: NSPanel?
    private var timer: Timer?
    private let size: CGFloat = 14
    private let cursorOffset = CGPoint(x: 16, y: -16)

    func show() {
        guard panel == nil else {
            update()
            return
        }
        let p = makePanel()
        panel = p
        update()
        p.orderFrontRegardless()
        // 60 Hz follow — cheap, NSEvent.mouseLocation is just a syscall.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.update() }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemRed.cgColor
        view.layer?.cornerRadius = size / 2
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        view.layer?.borderWidth = 1.5
        // Subtle pulse so the dot doesn't look frozen.
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.55
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        view.layer?.add(pulse, forKey: "pulse")
        p.contentView = view
        return p
    }

    private func update() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: mouse.x + cursorOffset.x, y: mouse.y + cursorOffset.y))
    }
}
