import AppKit

enum AppState {
    case loading
    case idle
    case recording
    case transcribing
    case error(String)
}

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let statusMenuItem: NSMenuItem
    private let modeItem: NSMenuItem
    private let hotkeyItem: NSMenuItem

    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenuItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        modeItem = NSMenuItem(title: "Mode: toggle", action: nil, keyEquivalent: "")
        modeItem.isEnabled = false
        hotkeyItem = NSMenuItem(title: "Hotkey: ⌘⇧Space", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false

        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(modeItem)
        menu.addItem(hotkeyItem)
        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        update(state: .loading)
        refreshSettingsLabels()
    }

    func update(state: AppState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .loading:
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Loading")
            button.title = " VoicePTT…"
            statusMenuItem.title = "Loading model…"
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Idle")
            button.title = ""
            statusMenuItem.title = "Ready"
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            button.title = " REC"
            statusMenuItem.title = "● Recording…"
        case .transcribing:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcribing")
            button.title = " …"
            statusMenuItem.title = "Transcribing…"
        case .error(let msg):
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
            button.title = " ERR"
            statusMenuItem.title = "Error: \(msg)"
        }
    }

    func refreshSettingsLabels() {
        modeItem.title = "Mode: \(Settings.shared.mode.rawValue)"
        hotkeyItem.title = "Hotkey: \(Settings.shared.hotkey.displayString)"
    }

    @objc private func openSettingsAction() { onOpenSettings?() }
    @objc private func quitAction() { onQuit?() }
}
