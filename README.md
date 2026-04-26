# VoicePTT

Push-to-talk dictation for macOS. Press a hotkey, speak, release — your speech is transcribed and pasted into the active window.

Runs entirely **on-device** on the Apple Neural Engine. No network calls, no API keys, no telemetry. Built on top of [FluidAudio](https://github.com/FluidInference/FluidAudio) (NVIDIA Parakeet TDT, CoreML).

Tested with English and Russian. The underlying Parakeet TDT v2/v3 models support 25 European languages.

---

## Requirements

| Component | Minimum | Recommended |
|---|---|---|
| macOS | 14.0 (Sonoma) | 15.x (Sequoia) |
| Hardware | Apple Silicon (M1+) | M2/M3/M4 with ANE |
| Disk space | ~3 GB free (model is ~2.5 GB) | — |
| RAM | 8 GB | 16 GB |
| Toolchain | Swift 5.10 (Xcode 15.x or Command Line Tools 15.x) | Swift 6.0+ for latest FluidAudio |

> Intel Macs are not supported — there is no Apple Neural Engine, and FluidAudio's CoreML models target Apple Silicon.

---

## Install

### Option 1 — Build from source (recommended for now, no prebuilt binaries yet)

```sh
git clone git@github.com:dmakhmutov/voice-ptt.git
cd voice-ptt
./build.sh
```

`build.sh` runs `swift build -c release`, packages the binary into `VoicePTT.app`, and applies an ad-hoc code signature.

When it finishes:

```sh
open VoicePTT.app
```

### Option 2 — Install Command Line Tools first (if you don't have Xcode)

```sh
xcode-select --install
# or, for a newer Swift toolchain (Swift 6, lets us use latest FluidAudio):
softwareupdate --list                     # find "Command Line Tools for Xcode-16.x"
softwareupdate -i "Command Line Tools for Xcode-16.4"
```

You don't need full Xcode — the Command Line Tools are enough.

---

## First-run setup

When you launch `VoicePTT.app` for the first time, you'll need to grant **two** permissions and wait for **one** download.

### 1. Microphone permission

macOS will pop up a dialog the first time the app tries to access the mic. Click **Allow**.

If you missed it: System Settings → Privacy & Security → **Microphone** → toggle on `VoicePTT`.

### 2. Accessibility permission (required for autopaste)

VoicePTT pastes the transcribed text by simulating `⌘V` keystrokes. macOS requires **Accessibility** permission for any app that synthesizes keystrokes.

System Settings → Privacy & Security → **Accessibility** → click `+` → add `VoicePTT.app` → ensure the toggle is on.

If you don't grant this, recording and transcription will still work, but the result won't be pasted automatically. You'll see it in the clipboard and can paste manually.

### 3. Model download (~2.5 GB, one-time)

On first launch, FluidAudio downloads the Parakeet TDT model from Hugging Face into:

```
~/Library/Application Support/FluidAudio/Models/
```

The menubar icon shows a `…` (ellipsis) while loading and switches to a 🎙 (mic) when ready. Depending on your connection this takes 1–5 minutes. Subsequent launches use the cached model and start in ~2–5 seconds.

To watch progress:

```sh
log stream --predicate 'process == "VoicePTT"' --level debug
```

Or open **Console.app** and filter by `VoicePTT`.

---

## Usage

### Default behavior

- **Hotkey**: `⌘⇧Space` (Cmd+Shift+Space)
- **Mode**: toggle — press once to start recording, press again to stop and transcribe
- **Output**: transcribed text is pasted into whatever app/field has focus

### Modes

| Mode | Behavior |
|---|---|
| **Toggle** | Press hotkey → recording starts. Press again → recording stops and text is pasted. |
| **Hold** | Hold hotkey → recording. Release → text is pasted. |

Choose in menubar → Settings…

### Changing the hotkey

Menubar → **Settings…** → click the hotkey field → press the new combination.

The hotkey must include at least one modifier (`⌘`, `⌥`, `⌃`, `⇧`) — single-key shortcuts aren't supported by the Carbon hotkey API.

---

## How it works

```
┌──────────────────┐
│ Carbon HotKey    │  Global ⌘⇧Space listener
└────────┬─────────┘
         │ keyDown / keyUp
┌────────▼─────────┐
│ AppDelegate      │  State machine: idle → recording → transcribing → idle
└────────┬─────────┘
         │ start/stop
┌────────▼─────────┐
│ AVAudioEngine    │  Tap input device, resample to 16 kHz mono Float32
└────────┬─────────┘
         │ [Float]
┌────────▼─────────┐
│ FluidAudio /     │  Parakeet TDT on Apple Neural Engine
│ AsrManager       │  Returns ASRResult { text, confidence, … }
└────────┬─────────┘
         │ String
┌────────▼─────────┐
│ NSPasteboard +   │  Save current clipboard, write text, post ⌘V,
│ CGEvent ⌘V       │  restore clipboard 0.3s later
└──────────────────┘
```

The whole thing is a thin Swift app around FluidAudio's Swift SDK. No Python, no Node, no FFI — just CoreML on the ANE.

---

## Performance

Roughly the same as [Kesha Voice Kit](https://github.com/drakulavich/kesha-voice-kit), since both call into the same FluidAudio engine.

| Phase | Duration |
|---|---|
| Cold start (first launch, model load) | 1–3 s |
| Warm start | <1 s |
| Recording | real-time |
| Transcription of 5 s of speech (M2/M3) | ~300–400 ms |
| Resample 48 kHz → 16 kHz | <10 ms |
| Clipboard write + ⌘V dispatch | <5 ms |
| **End-to-end (release hotkey → text appears)** | **~0.5 s** |

---

## Troubleshooting

**App opens but nothing happens.** It's a menubar-only app (`LSUIElement` = true). Look for the mic icon in the top-right of your screen, not the Dock.

**Hotkey doesn't trigger anything.** Check that the menubar status says "Ready" (not "Loading model…"). If still "Loading…", the Parakeet model is still downloading — check Console.app.

**Text doesn't get pasted into the focused field.** Accessibility permission missing. See [First-run setup](#2-accessibility-permission-required-for-autopaste).

**`build.sh` fails with "incompatible tools version (6.0.0)".** Your Swift toolchain is older than 6.0 and you're trying to use a recent FluidAudio. The `Package.swift` in this repo pins to FluidAudio `0.7.0..<0.9.0` to stay Swift 5.10-compatible. If you want the latest FluidAudio (0.12+), upgrade to Command Line Tools 16+ (`softwareupdate -i "Command Line Tools for Xcode-16.4"`) and bump the version in `Package.swift`.

**`xcrun: error: unable to lookup item 'PlatformPath'`.** Cosmetic warning from `swift build`. The build still succeeds. Caused by the Command Line Tools not exposing the macOS platform path that XCTest expects. Safe to ignore.

**Recorded audio sounds clipped or muffled.** AVAudioEngine uses your **default input device**. Check System Settings → Sound → Input.

**App says "Error: kAudioHardwareNotRunningError" or similar.** Some other app may be holding the input device. Restart VoicePTT, or unplug/replug your USB mic.

---

## Development

```sh
# debug build
swift build

# run from source (the binary will appear in the Dock — no LSUIElement when run this way)
swift run VoicePTT

# clean
swift package clean
rm -rf .build VoicePTT.app

# show resolved dependency versions
swift package show-dependencies
```

### Project layout

```
voice-ptt/
├── Package.swift                      # SwiftPM manifest, FluidAudio dependency
├── build.sh                           # Builds + packages .app + ad-hoc codesign
├── Resources/Info.plist               # Bundle metadata, permission strings
└── Sources/VoicePTT/
    ├── EntryPoint.swift               # @main, NSApplication setup
    ├── AppDelegate.swift              # Wires hotkey → recorder → transcriber → paster
    ├── Settings.swift                 # UserDefaults persistence (mode, hotkey)
    ├── HotkeyManager.swift            # Carbon RegisterEventHotKey
    ├── AudioRecorder.swift            # AVAudioEngine + AVAudioConverter (→ 16 kHz Float)
    ├── Transcriber.swift              # FluidAudio AsrManager wrapper
    ├── Paster.swift                   # NSPasteboard + CGEvent ⌘V
    ├── MenuBarController.swift        # NSStatusItem, state-aware icon
    └── SettingsWindow.swift           # SwiftUI Form with hotkey recorder
```

### Useful one-liners

```sh
# stream app logs
log stream --predicate 'process == "VoicePTT"'

# tail crash reports
ls -lt ~/Library/Logs/DiagnosticReports/ | grep -i voiceptt | head -3

# inspect the FluidAudio public API (after first build)
grep -rn 'public func' .build/checkouts/FluidAudio/Sources/FluidAudio/ASR/

# check what model files were downloaded
ls -la "$HOME/Library/Application Support/FluidAudio/Models/"
```

---

## Roadmap

- [x] Push-to-talk hotkey + paste-at-end transcription
- [x] Settings window (configurable mode + hotkey)
- [x] Menubar status indicator
- [ ] Live streaming transcription (text appears as you speak — branch `feature/live-typing`)
- [ ] Toggle between Russian-only / English-only / auto-detect (small latency win)
- [ ] Auto-launch at login
- [ ] Notarized prebuilt `.dmg`

---

## Credits

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Swift SDK that does the actual ASR. We're a thin UX wrapper around it.
- [NVIDIA Parakeet TDT](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — the speech-recognition model.
- Inspired by [Kesha Voice Kit](https://github.com/drakulavich/kesha-voice-kit) (Rust + same FluidAudio under the hood).

## License

MIT (see `LICENSE` once added).
