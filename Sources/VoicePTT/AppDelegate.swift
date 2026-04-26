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

    private var modelDownloadTimer: Timer?
    private var modelLoadStartTime: Date?
    private var lastCacheBytes: Int64 = 0
    private var stableCacheTicks = 0

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

        // System notifications are an opt-in nicety; we deliver the same
        // info via the floating HUD which doesn't need any permission.
        // Calling notify(...) without auth is a silent no-op, so we keep
        // the notify() calls in case the user has system notifications
        // turned on for the app, but we no longer prompt for the perm.
        // Persistent HUD until the model finishes loading. First-time
        // download can take a couple of minutes; even on cached launches
        // CoreML compilation for the Neural Engine costs ~15s on first
        // boot. The progress timer below keeps the message honest.
        let isFirstDownload = !ModelStorage.shared.hasAnyCachedModel
        let loadingMessage = isFirstDownload
            ? "Downloading speech model…\nFirst time only, \(ModelInfo.sizeDescription)"
            : "Loading speech model…"
        hud.show(loadingMessage, duration: nil)
        notify(
            title: "VoicePTT",
            body: isFirstDownload ? "Downloading model (\(ModelInfo.sizeDescription))…" : "Loading model…"
        )
        startModelLoadProgress()

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
                self.stopModelLoadProgress()
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

        // Background update probe — at most once per 24h. If a newer release
        // is found, surface it via the HUD + a notification.
        Task { [weak self] in
            await UpdateChecker.shared.checkIfStale()
            if case .updateAvailable(let info) = UpdateChecker.shared.status {
                await MainActor.run {
                    self?.hud.show("⬇ Update available: v\(info.version)", duration: 6.0)
                    self?.notify(
                        title: "VoicePTT update v\(info.version)",
                        body: "Open Settings → Updates to download."
                    )
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

    /// Polls the model cache directory size + elapsed time and pushes a
    /// progress message into the HUD. FluidAudio 0.8.x's
    /// `AsrModels.downloadAndLoad()` doesn't expose real progress, so we
    /// detect the lifecycle phase from observable side-effects:
    ///   1. *Setting up*    — cache empty, no bytes yet (just started).
    ///   2. *Downloading*   — bytes growing on disk; show MB / total + ETA.
    ///   3. *Preparing*     — cache size stable for several ticks (download
    ///      done, FluidAudio is now compiling models for the Neural Engine,
    ///      which can add ~15 seconds on first boot).
    /// Always include elapsed time so the user knows things are moving.
    private func startModelLoadProgress() {
        modelDownloadTimer?.invalidate()
        modelLoadStartTime = Date()
        lastCacheBytes = ModelStorage.shared.currentCacheBytes()
        stableCacheTicks = 0
        modelDownloadTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickModelLoadProgress()
            }
        }
    }

    private func tickModelLoadProgress() {
        guard let started = modelLoadStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(started))
        let timeStr = String(format: "%d:%02d", elapsed / 60, elapsed % 60)

        let bytes = ModelStorage.shared.currentCacheBytes()
        let mb = Int(bytes / (1024 * 1024))
        let expectedMB = Int(ModelInfo.expectedSizeMB)

        if bytes == lastCacheBytes && mb >= 50 {
            stableCacheTicks += 1
        } else {
            stableCacheTicks = 0
        }
        lastCacheBytes = bytes

        // Cache stable for 3+ seconds OR almost-full → assume download done,
        // CoreML is compiling.
        let downloadDone = stableCacheTicks >= 3 || mb >= expectedMB - 20

        let message: String
        if mb < 10 {
            message = "Setting up speech model… (\(timeStr))"
        } else if downloadDone {
            message = "Preparing model for Neural Engine… (\(timeStr))"
        } else {
            message = "Downloading model — \(mb)/\(expectedMB) MB (\(timeStr))"
        }
        hud.update(message)
    }

    private func stopModelLoadProgress() {
        modelDownloadTimer?.invalidate()
        modelDownloadTimer = nil
        modelLoadStartTime = nil
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
