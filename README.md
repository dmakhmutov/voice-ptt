# VoicePTT

Push-to-talk dictation for macOS. Press a hotkey, speak, release — your speech is transcribed and pasted into the active window.

Runs entirely **on-device** on the Apple Neural Engine. No network calls, no API keys, no telemetry. Built on top of [FluidAudio](https://github.com/FluidInference/FluidAudio) (NVIDIA Parakeet TDT, CoreML).

Tested with English and Russian. The underlying Parakeet TDT v2/v3 models support 25 European languages.

---

## Quick install

### Option A — Download the prebuilt app (recommended for users)

1. Grab `VoicePTT-X.Y.zip` from the **[latest release](https://github.com/dmakhmutov/voice-ptt/releases/latest)**
2. Unzip → drag `VoicePTT.app` to `/Applications` (or anywhere you like)
3. **Right-click `VoicePTT.app` → Open** the first time. macOS shows a "developer cannot be verified" warning because the app uses a self-signed certificate — click **Open** in the dialog. Subsequent launches work normally.
4. The Settings window opens automatically — grant **Microphone** and **Accessibility** (the panel has direct buttons), wait for the model to download (~500 MB, one-time), press `⌘⇧Space` and dictate

### Option B — Build from source (for contributors)

```sh
git clone git@github.com:dmakhmutov/voice-ptt.git
cd voice-ptt
./build.sh
open VoicePTT.app
```

> *(Optional, recommended)* Before the first build, create a self-signed code-signing cert named `VoicePTT Local` once via **Keychain Access → Certificate Assistant → Create a Certificate…** → `Code Signing` type. `build.sh` auto-uses it; without it, you'll have to re-grant Accessibility after every rebuild.

If anything below the Quick install applies to you (you don't have Xcode installed, you hit a build error, you need to know what's actually happening), keep reading.

---

## Requirements

| Component | Minimum | Recommended |
|---|---|---|
| macOS | 14.0 (Sonoma) | 15.x (Sequoia) |
| Hardware | Apple Silicon (M1+) | M2/M3/M4 with ANE |
| Disk space | ~1 GB free (model is ~500 MB) | — |
| RAM | 8 GB | 16 GB |
| Toolchain | Swift 5.10 (Xcode 15.x or Command Line Tools 15.x) | Swift 6.0+ for latest FluidAudio |

> Intel Macs are not supported — there is no Apple Neural Engine, and FluidAudio's CoreML models target Apple Silicon.

---

## First-run details

Quick install above covers the happy path. This section has the extra detail you might want.

**No Xcode? Install just the Command Line Tools** — full Xcode isn't needed, the CLT are enough:

```sh
xcode-select --install
# or, for a newer Swift toolchain (Swift 6, needed for latest FluidAudio):
softwareupdate -i "Command Line Tools for Xcode-16.4"
```

**Missed a permission dialog?** Open the app's Settings (menubar → Settings…). The Status panel at the top shows what's granted and gives you direct buttons to the right System Settings pane for each missing permission.

**Where the model lives:** `~/Library/Application Support/FluidAudio/Models/`. ~500 MB (CoreML-quantized Parakeet TDT), downloaded once on first launch from Hugging Face. Subsequent launches reuse the cache and start in 2–5 seconds.

**Watching the model load progress** or any logs:

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

**Have to re-add the app to Accessibility every time I rebuild.** macOS ties the Accessibility grant to the app's code signature. With ad-hoc signing each build gets a different signature, so the grant doesn't apply. Fix once: create a self-signed code-signing certificate via Keychain Access (`Certificate Assistant → Create a Certificate…`, name `VoicePTT Local`, type `Code Signing`, leave the override-defaults checkbox off). `build.sh` auto-detects this cert and uses it; subsequent rebuilds keep the same signature and the Accessibility grant sticks.

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
├── build.sh                           # swift build → .app bundle → codesign
├── Resources/Info.plist               # Bundle metadata, permission strings
└── Sources/VoicePTT/
    ├── EntryPoint.swift               # @main, NSApplication setup
    ├── AppDelegate.swift              # Wires hotkey → recorder → transcriber → paster
    ├── Settings.swift                 # UserDefaults: mode, hotkey, launchAtLogin
    ├── HotkeyManager.swift            # Carbon RegisterEventHotKey
    ├── AudioRecorder.swift            # AVAudioEngine → 16 kHz Float
    ├── Transcriber.swift              # FluidAudio AsrManager wrapper
    ├── Paster.swift                   # NSPasteboard + CGEvent ⌘V
    ├── LoginItem.swift                # SMAppService.mainApp register/unregister
    ├── AppStatus.swift                # Observed permission/model state
    ├── PermissionsView.swift          # Status panel in Settings
    ├── MenuBarController.swift        # NSStatusItem, state-aware icon
    ├── StatusHUD.swift                # Floating "ready" panel on launch
    ├── RecordingIndicator.swift       # Cursor-following red dot while recording
    └── SettingsWindow.swift           # SwiftUI Form
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

## Credits

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Swift SDK that does the actual ASR. We're a thin UX wrapper around it.
- [NVIDIA Parakeet TDT](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — the speech-recognition model.
- Inspired by [Kesha Voice Kit](https://github.com/drakulavich/kesha-voice-kit) (Rust + same FluidAudio under the hood).

## License

MIT — see [`LICENSE`](LICENSE).
