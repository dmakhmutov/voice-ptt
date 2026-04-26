import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    var onChange: (() -> Void)?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView { [weak self] in self?.onChange?() }
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "VoicePTT — Settings"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 380, height: 200))
        win.center()
        win.isReleasedWhenClosed = false
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    @State private var mode: HotkeyMode = Settings.shared.mode
    @State private var hotkey: HotkeyBinding = Settings.shared.hotkey
    @State private var launchAtLogin: Bool = Settings.shared.launchAtLogin
    let onChange: () -> Void

    var body: some View {
        Form {
            Picker("Mode", selection: $mode) {
                Text("Toggle (press — record, press — stop)").tag(HotkeyMode.toggle)
                Text("Hold (hold — record, release — stop)").tag(HotkeyMode.hold)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: mode) { _, newValue in
                Settings.shared.mode = newValue
                onChange()
            }

            Divider()

            HStack {
                Text("Hotkey:")
                HotkeyRecorderView(binding: $hotkey)
                    .frame(minWidth: 180, minHeight: 28)
                    .onChange(of: hotkey) { _, newValue in
                        Settings.shared.hotkey = newValue
                        onChange()
                    }
            }

            Divider()

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    Settings.shared.launchAtLogin = newValue
                    LoginItem.set(enabled: newValue)
                    onChange()
                }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var binding: HotkeyBinding

    func makeNSView(context: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField()
        field.binding = binding
        field.onChange = { binding = $0 }
        return field
    }

    func updateNSView(_ nsView: HotkeyRecorderField, context: Context) {
        nsView.binding = binding
        nsView.refresh()
    }
}

final class HotkeyRecorderField: NSView {
    var binding: HotkeyBinding = .default
    var onChange: ((HotkeyBinding) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var recording = false
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        label.stringValue = recording ? "Press a shortcut…" : binding.displayString
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        recording.toggle()
        if recording { startMonitor() } else { stopMonitor() }
        refresh()
    }

    private func startMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let cocoaFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var carbonFlags: UInt32 = 0
            if cocoaFlags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
            if cocoaFlags.contains(.shift)   { carbonFlags |= UInt32(shiftKey) }
            if cocoaFlags.contains(.option)  { carbonFlags |= UInt32(optionKey) }
            if cocoaFlags.contains(.control) { carbonFlags |= UInt32(controlKey) }
            guard carbonFlags != 0 else { return event }
            let new = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: carbonFlags)
            self.binding = new
            self.onChange?(new)
            self.recording = false
            self.stopMonitor()
            self.refresh()
            return nil
        }
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
