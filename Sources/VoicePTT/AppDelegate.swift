import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menubar = MenuBarController()
    private let settingsWindow = SettingsWindowController()
    private let hotkey = HotkeyManager()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menubar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        menubar.onQuit = { NSApp.terminate(nil) }
        settingsWindow.onChange = { [weak self] in self?.applySettings() }

        configureHotkeyCallbacks()
        applySettings()

        Task { [weak self] in
            await self?.transcriber.load()
            await MainActor.run {
                guard let self else { return }
                if case .ready = self.transcriber.state {
                    self.menubar.update(state: .idle)
                } else if case .failed(let err) = self.transcriber.state {
                    self.menubar.update(state: .error(err.localizedDescription))
                }
            }
        }
    }

    private func applySettings() {
        hotkey.register(Settings.shared.hotkey)
        menubar.refreshSettingsLabels()
    }

    private func configureHotkeyCallbacks() {
        hotkey.onKeyDown = { [weak self] in self?.handleKeyDown() }
        hotkey.onKeyUp = { [weak self] in self?.handleKeyUp() }
    }

    private func handleKeyDown() {
        switch Settings.shared.mode {
        case .toggle:
            if isRecording { finishRecording() } else { beginRecording() }
        case .hold:
            if !isRecording { beginRecording() }
        }
    }

    private func handleKeyUp() {
        if Settings.shared.mode == .hold, isRecording {
            finishRecording()
        }
    }

    private func beginRecording() {
        guard case .ready = transcriber.state else {
            NSSound.beep()
            return
        }
        do {
            try recorder.start()
            isRecording = true
            menubar.update(state: .recording)
        } catch {
            NSLog("VoicePTT: recorder start failed: \(error)")
            menubar.update(state: .error("\(error)"))
        }
    }

    private func finishRecording() {
        let samples = recorder.stop()
        isRecording = false
        menubar.update(state: .transcribing)

        Task { [weak self] in
            guard let self else { return }
            let text = await self.transcriber.transcribe(samples)
            await MainActor.run {
                if let text, !text.isEmpty {
                    Paster.paste(text)
                }
                self.menubar.update(state: .idle)
            }
        }
    }
}
