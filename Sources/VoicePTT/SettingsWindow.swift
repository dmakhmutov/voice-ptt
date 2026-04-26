import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    var onChange: (() -> Void)?
    /// Returns the recognized text (or a short error message). Set by AppDelegate.
    var onTestRecording: (() async -> String)?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            onChange: { [weak self] in self?.onChange?() },
            onTestRecording: { [weak self] in
                await self?.onTestRecording?() ?? ""
            }
        )
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "VoicePTT — Settings"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 460, height: 760))
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
    @ObservedObject private var status = AppStatus.shared
    let onChange: () -> Void
    let onTestRecording: () async -> String

    var body: some View {
        Form {
            PermissionsSection(status: status)
                .onAppear { status.refreshPermissions() }
                .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                    status.refreshPermissions()
                }

            Divider()

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

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        Settings.shared.launchAtLogin = newValue
                        LoginItem.set(enabled: newValue)
                        onChange()
                    }

                Text("First time you enable this, macOS may show a notification asking to approve the login item. If it doesn't appear in the list below, open System Settings and toggle VoicePTT on manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Login Items in System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }

            Divider()

            TestRecordingSection(onRun: onTestRecording)

            Divider()

            UpdateSection()

            Divider()

            ModelStorageSection()
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct ModelStorageSection: View {
    @ObservedObject private var storage = ModelStorage.shared
    @State private var confirmClear = false

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB, .useKB]
        f.countStyle = .file
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Model storage").font(.headline)
                Spacer()
                Button("Open in Finder") { storage.openInFinder() }
                    .controlSize(.small)
            }

            Text(storage.cachePathDisplay)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if storage.entries.isEmpty {
                Text("Cache is empty. Models will download on the next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(storage.entries) { entry in
                        HStack(spacing: 8) {
                            Text(entry.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Self.formatter.string(fromByteCount: entry.size))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button {
                                storage.remove(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("Delete \(entry.name)")
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)

                HStack {
                    Text("Total: \(Self.formatter.string(fromByteCount: storage.totalSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear all", role: .destructive) { confirmClear = true }
                        .controlSize(.small)
                }
            }
        }
        .onAppear { storage.refresh() }
        .alert("Clear all model caches?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { storage.clearAll() }
        } message: {
            Text("This deletes \(Self.formatter.string(fromByteCount: storage.totalSize)) from \(storage.cachePathDisplay). The active model will redownload on the next launch (~2.5 GB).")
        }
    }
}

private struct UpdateSection: View {
    @ObservedObject private var checker = UpdateChecker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Updates").font(.headline)
                Spacer()
                Button("Check now") {
                    Task { await checker.check() }
                }
                .controlSize(.small)
                .disabled(isChecking)
            }

            content
        }
    }

    private var isChecking: Bool {
        if case .checking = checker.status { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch checker.status {
        case .unknown:
            Text("Current version: \(checker.ownVersion). Click 'Check now' to look for new releases.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            Text("Checking GitHub…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .upToDate(let v):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Up to date — running v\(v).").font(.caption).foregroundStyle(.secondary)
            }
        case .updateAvailable(let info):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                    Text("Update available: v\(info.version)").fontWeight(.medium)
                }
                if !info.body.isEmpty {
                    Text(info.body.prefix(200) + (info.body.count > 200 ? "…" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                installActionRow(info: info)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange, lineWidth: 1))
            .cornerRadius(6)
        case .error(let msg):
            Text("Couldn't check: \(msg)").font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func installActionRow(info: UpdateInfo) -> some View {
        switch checker.installState {
        case .idle:
            HStack {
                Button {
                    Task { await checker.downloadAndInstall(info) }
                } label: {
                    Label("Download & install", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)
                .disabled(info.assetURL == nil)

                Button("Open release page") {
                    NSWorkspace.shared.open(info.pageURL)
                }
                .controlSize(.small)
            }
        case .downloading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Downloading…").font(.caption).foregroundStyle(.secondary)
            }
        case .unzipping:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Unpacking…").font(.caption).foregroundStyle(.secondary)
            }
        case .relaunching:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Restarting with the new version…").font(.caption).foregroundStyle(.secondary)
            }
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 4) {
                Text("Install failed: \(msg)").font(.caption).foregroundStyle(.red)
                Button("Try again") {
                    checker.installState = .idle
                }
                .controlSize(.small)
            }
        }
    }
}

private struct TestRecordingSection: View {
    let onRun: () async -> String
    @State private var isRunning = false
    @State private var result: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Test recording").font(.headline)
                Spacer()
                Button(action: run) {
                    if isRunning {
                        Label("Recording 3s…", systemImage: "mic.fill")
                    } else {
                        Label("Run 3-second test", systemImage: "mic")
                    }
                }
                .disabled(isRunning)
                .controlSize(.small)
            }

            if result.isEmpty {
                Text("Click the button, then speak any phrase. The recognized text appears below — handy for verifying the mic + model + permissions all work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(result)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50, maxHeight: 100)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }
        }
    }

    private func run() {
        Task {
            isRunning = true
            result = await onRun()
            isRunning = false
        }
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
