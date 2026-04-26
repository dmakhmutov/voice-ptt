import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menubar = MenuBarController()
    private let settingsWindow = SettingsWindowController()
    private let hotkey = HotkeyManager()
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let hud = StatusHUD()
    private let recordingIndicator = RecordingIndicator()
    private var isRecording = false

    /// Hard cap on recording duration. Protects against a stuck hotkey or a
    /// user who walked away with the app still recording — buffers grow
    /// linearly with audio length and FluidAudio's batch transcribe slows
    /// down on very long inputs.
    private static let maxRecordingDuration: TimeInterval = 120
    private var maxDurationTask: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menubar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        menubar.onQuit = { NSApp.terminate(nil) }
        settingsWindow.onChange = { [weak self] in self?.applySettings() }
        settingsWindow.onTestRecording = { [weak self] in
            await self?.runTestRecording() ?? "App unavailable"
        }

        configureHotkeyCallbacks()
        applySettings()
        LoginItem.sync(with: Settings.shared.launchAtLogin)
        AppStatus.shared.refreshPermissions()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in AppStatus.shared.refreshPermissions() }
        }
        hud.show("VoicePTT loading model…", duration: 5.0)
        notify(title: "VoicePTT", body: "Loading model…")

        if !UserDefaults.standard.bool(forKey: "app.firstLaunchCompleted") {
            UserDefaults.standard.set(true, forKey: "app.firstLaunchCompleted")
            // Open Settings so the user sees the Status panel and can grant
            // any missing permissions without hunting through the menubar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.settingsWindow.show()
            }
        }

        Task { [weak self] in
            await self?.transcriber.load()
            await MainActor.run {
                guard let self else { return }
                if case .ready = self.transcriber.state {
                    self.menubar.update(state: .idle)
                    AppStatus.shared.modelLoaded = true
                    let hk = Settings.shared.hotkey.displayString
                    self.hud.show("🎙 VoicePTT ready — \(hk)")
                    self.notify(title: "VoicePTT ready", body: "Press \(hk) to dictate")
                } else if case .failed(let err) = self.transcriber.state {
                    self.menubar.update(state: .error(err.localizedDescription))
                    self.hud.show("⚠️ VoicePTT failed: \(err.localizedDescription)", duration: 6.0)
                    self.notify(title: "VoicePTT failed to start", body: err.localizedDescription)
                }
            }
        }
    }

    /// Records 3 seconds, transcribes, returns the recognized text.
    /// Used by the "Test recording" button in Settings to verify the pipeline
    /// without going through a real hotkey session.
    func runTestRecording() async -> String {
        guard case .ready = transcriber.state else {
            return "Model not ready yet — wait a few seconds for it to load."
        }
        if isRecording {
            return "A hotkey recording is already in progress — stop it first."
        }
        do {
            try recorder.start()
        } catch {
            return "Recorder failed to start: \(error.localizedDescription)"
        }
        recordingIndicator.show()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let samples = recorder.stop()
        recordingIndicator.hide()
        let text = await transcriber.transcribe(samples) ?? ""
        return text.isEmpty ? "(no speech detected)" : text
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
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
            recordingIndicator.show()
            scheduleMaxDurationTimeout()
        } catch {
            NSLog("VoicePTT: recorder start failed: \(error)")
            menubar.update(state: .error("\(error)"))
        }
    }

    private func finishRecording() {
        cancelMaxDurationTimeout()
        let samples = recorder.stop()
        isRecording = false
        recordingIndicator.hide()
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

    private func scheduleMaxDurationTimeout() {
        cancelMaxDurationTimeout()
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            let secs = Int(Self.maxRecordingDuration)
            NSLog("VoicePTT: hit max recording duration (\(secs)s), auto-stopping")
            self.hud.show("⏱ Auto-stopped after \(secs)s", duration: 4.0)
            self.finishRecording()
        }
        maxDurationTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxRecordingDuration, execute: task)
    }

    private func cancelMaxDurationTimeout() {
        maxDurationTask?.cancel()
        maxDurationTask = nil
    }
}
