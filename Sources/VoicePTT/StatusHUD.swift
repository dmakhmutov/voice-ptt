import AppKit

/// A small floating status panel for short-lived "I'm alive" feedback when the
/// menubar icon may be hidden (e.g. behind the notch on MacBooks with a crowded
/// menu bar). Shows in the top-right corner, auto-dismisses after a few seconds.
@MainActor
final class StatusHUD {
    private var panel: NSPanel?
    private weak var label: NSTextField?
    private var hideTask: DispatchWorkItem?

    /// `duration: nil` keeps the HUD up indefinitely until `hide()` is called
    /// or another `show(...)` call replaces the message and timer.
    func show(_ message: String, duration: TimeInterval? = 3.0) {
        let panel = self.panel ?? makePanel()
        label?.stringValue = message
        sizeAndPosition(panel)
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = nil
        guard let duration else { return }
        let task = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
    }

    /// Updates the message text without re-showing or re-positioning the
    /// panel. Use this for high-frequency updates (e.g. download progress
    /// ticks); calling `show(...)` repeatedly would flicker.
    func update(_ message: String) {
        label?.stringValue = message
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.autoresizingMask = [.width, .height]
        bg.blendingMode = .behindWindow
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        panel.contentView = bg

        let lbl = NSTextField(labelWithString: "")
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13, weight: .medium)
        lbl.alignment = .center
        lbl.maximumNumberOfLines = 2
        lbl.lineBreakMode = .byTruncatingTail
        bg.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            lbl.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            lbl.centerYAnchor.constraint(equalTo: bg.centerYAnchor)
        ])

        self.panel = panel
        self.label = lbl
        return panel
    }

    private func sizeAndPosition(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.maxX - panel.frame.width - 20
        let y = frame.maxY - panel.frame.height - 20
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
