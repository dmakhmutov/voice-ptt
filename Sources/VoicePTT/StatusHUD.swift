import AppKit

/// A small floating status panel for short-lived "I'm alive" feedback when the
/// menubar icon may be hidden (e.g. behind the notch on MacBooks with a crowded
/// menu bar). Shows in the top-right corner, auto-dismisses after a few seconds.
@MainActor
final class StatusHUD {
    private var panel: NSPanel?
    private weak var label: NSTextField?
    private weak var iconView: NSImageView?
    private var hideTask: DispatchWorkItem?

    /// `duration: nil` keeps the HUD up indefinitely until `hide()` is called
    /// or another `show(...)` call replaces the message and timer.
    func show(_ message: String, systemImage: String? = nil, duration: TimeInterval? = 3.0) {
        let panel = self.panel ?? makePanel()
        applyContent(message: message, systemImage: systemImage)
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

    /// Updates the message without re-showing or re-positioning the panel.
    /// Use for high-frequency updates (e.g. download progress ticks); calling
    /// `show(...)` repeatedly would flicker the panel.
    func update(_ message: String, systemImage: String? = nil) {
        applyContent(message: message, systemImage: systemImage)
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
    }

    private func applyContent(message: String, systemImage: String?) {
        label?.stringValue = message
        if let systemImage,
           let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
               .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold)) {
            iconView?.image = img
            iconView?.isHidden = false
        } else {
            iconView?.image = nil
            iconView?.isHidden = true
        }
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
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        panel.contentView = bg

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .labelColor
        icon.symbolConfiguration = .init(pointSize: 17, weight: .semibold)

        let lbl = NSTextField(labelWithString: "")
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13, weight: .semibold)
        lbl.maximumNumberOfLines = 2
        lbl.lineBreakMode = .byTruncatingTail
        lbl.allowsDefaultTighteningForTruncation = true

        let stack = NSStackView(views: [icon, lbl])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.detachesHiddenViews = true
        bg.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: bg.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bg.trailingAnchor, constant: -16),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
        ])

        self.panel = panel
        self.label = lbl
        self.iconView = icon
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
