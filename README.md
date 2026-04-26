# VoicePTT

Push-to-talk dictation for macOS. Press a hotkey (or hold Right ⌘), speak, release — your speech is transcribed and pasted into the active window.

Runs entirely **on-device** on the Apple Neural Engine. No network calls, no API keys, no telemetry. Built on top of [FluidAudio](https://github.com/FluidInference/FluidAudio) (NVIDIA Parakeet TDT, CoreML).

Tested with English and Russian. The underlying Parakeet TDT v3 model supports 25 European languages.

---

## Quick install

### Option A — Download the prebuilt app (recommended)

1. Grab `VoicePTT-X.Y.zip` from the **[latest release](https://github.com/dmakhmutov/voice-ptt/releases/latest)**
2. Unzip → drag `VoicePTT.app` to `/Applications` (or anywhere you like)
3. **Right-click `VoicePTT.app` → Open** the first time. macOS shows a "developer cannot be verified" warning because the app uses a self-signed certificate — click **Open** in the dialog. Subsequent launches work normally.
4. The Settings window opens automatically — grant **Microphone** and **Accessibility** (the Status panel has direct buttons for each), wait for the model to download (~500 MB, one-time), press `⌘⇧Space` and dictate.

Once installed, future updates ship in-app: **Settings → Updates → Check now → Download & install** does everything for you (download, swap, relaunch on the new version).

### Option B — Build from source

```sh
git clone git@github.com:dmakhmutov/voice-ptt.git
cd voice-ptt
./build.sh
open VoicePTT.app
```

> *(Optional, recommended)* Before the first build, create a self-signed code-signing cert named `VoicePTT Local` once via **Keychain Access → Certificate Assistant → Create a Certificate…** → `Code Signing` type. `build.sh` auto-uses it; without it, you'll have to re-grant Accessibility after every rebuild.

`build.sh` also auto-restarts the app if it's already running, so the dev loop is `edit → ./build.sh → done`.

---

## Requirements

| Component | Minimum | Recommended |
|---|---|---|
| macOS | 14.0 (Sonoma) | 15.x (Sequoia) |
| Hardware | Apple Silicon (M1+) | M2/M3/M4 with ANE |
| Disk space | ~1 GB free (model is ~500 MB) | — |
| RAM | 8 GB | 16 GB |
| Toolchain (build from source only) | Swift 5.10 (Xcode 15.x or Command Line Tools 15.x) | Swift 6.0+ for latest FluidAudio |

> Intel Macs are not supported — there is no Apple Neural Engine, and FluidAudio's CoreML models target Apple Silicon.

---

## Usage

### Triggers (pick one in Settings → Behavior)

| Trigger | How |
|---|---|
| **Custom hotkey** (default `⌘⇧Space`) | Configurable via the hotkey recorder field. Must include at least one modifier — Carbon's hotkey API doesn't allow plain keys. Mode: *toggle* (press to start, press again to stop) or *hold* (hold to record, release to stop). |
| **Right ⌘** | Hold Right ⌘ alone (no other modifiers — `Right ⌘+C` still copies). Always hold-style. Useful if you don't want to remember a combo. |

### What happens when you record

1. **Cursor red dot** pulses near your pointer while recording — distinct from macOS's own orange mic-in-use indicator in the menubar.
2. **Auto-stop after 120 seconds** if you forget you're recording (e.g., stuck hotkey). Whatever was captured still gets transcribed and pasted.
3. On stop, the transcript is **pasted into the focused window** via clipboard + synthesized `⌘V`. The previous clipboard contents are restored ~0.3 s later.

### Settings window

Opens automatically on every user-initiated launch (Finder double-click, Spotlight, Alfred, `open VoicePTT.app`). Auto-launch via login item stays silent. Press `Esc` to close.

Sections, top to bottom:

- **Status** — green check / orange warning for Microphone, Accessibility, and the speech model. Each missing permission has an "Open Settings" button that deep-links to the right System Settings pane.
- **Behavior** — Trigger picker, hotkey recorder, mode toggle, Launch at login.
- **Test recording** — record 3 seconds and see what's transcribed, without leaving Settings. Quick check that mic + model + permissions are wired up.
- **Updates** — current version, "Check now" button, and (when applicable) "Download & install" to swap in the latest release with one click.
- **Model storage** — list of cached model directories with sizes; per-entry trash button or "Clear all" to free disk space. The active model re-downloads on next launch.

---

## First-run details

The Quick install above covers the happy path. This section has the extra detail you might want.

**No Xcode? Install just the Command Line Tools** — full Xcode isn't needed:

```sh
xcode-select --install
# or, for a newer Swift toolchain (Swift 6, needed for latest FluidAudio):
softwareupdate -i "Command Line Tools for Xcode-16.4"
```

**Missed a permission dialog?** Open Settings (menubar → Settings… or relaunch the app). The Status panel shows what's granted and gives direct "Open Settings" buttons.

**Where the model lives:** `~/Library/Application Support/FluidAudio/Models/`. ~500 MB (CoreML-quantized Parakeet TDT), downloaded once on first launch from Hugging Face. Subsequent launches reuse the cache and start in 2–5 seconds.

**Watching the model load progress** — the floating HUD plate at top-right shows phases ("Setting up… → Downloading model — N/500 MB → Preparing model for Neural Engine… → Ready") with elapsed time. For verbose logs:

```sh
log stream --predicate 'process == "VoicePTT"' --level debug
```

---

## How it works

```
┌──────────────────┐         ┌──────────────────┐
│ Carbon HotKey    │   OR    │ Right ⌘ Monitor   │
│ (combo)          │         │ (modifier-only)  │
└────────┬─────────┘         └────────┬─────────┘
         │ keyDown / keyUp / press / release
         ▼
┌──────────────────┐
│ AppDelegate      │  State machine: idle → recording → transcribing → idle
└────────┬─────────┘
         │ start/stop
┌────────▼─────────┐
│ AVAudioEngine    │  Tap input device, copy buffer
└────────┬─────────┘
         │ AVAudioPCMBuffer
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

Around the recording pipeline:

- **`StatusHUD`** — floating panel for launch progress and post-recording errors.
- **`RecordingIndicator`** — pulsing red dot that follows the cursor at 60 Hz during recording.
- **`MenuBarController`** — `NSStatusItem` whose icon and text reflect state (loading / ready / recording / transcribing / error).
- **`UpdateChecker`** — polls GitHub Releases API every 24h, downloads + unzips + relaunches via a hardened `/bin/sh -c` helper.
- **`AppStatus`** — observable singleton consumed by SwiftUI's Settings panel for live permission state.

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
| Clipboard write + ⌘V dispatch | <5 ms |
| **End-to-end (release hotkey → text appears)** | **~0.5 s** |

---

## Troubleshooting

**App opens but nothing happens.** It's a menubar-only app (`LSUIElement` = true). Look for the mic icon in the top-right of your screen, not the Dock. To re-open the Settings window, launch the app again from Finder/Alfred — that gesture re-opens Settings.

**Hotkey doesn't trigger anything.** Open Settings → check the Status panel. If anything's orange, click its "Open Settings" button to grant. If everything's green, try the **Test recording** button to confirm the pipeline.

**Text doesn't get pasted into the focused field.** Accessibility permission missing. Status panel will flag it with "Open Settings" → System Settings → Privacy & Security → Accessibility → toggle VoicePTT on.

**`build.sh` fails with "incompatible tools version (6.0.0)".** Your Swift toolchain is older than 6.0 and you're trying to use a recent FluidAudio. The `Package.swift` in this repo pins to FluidAudio `0.7.0..<0.9.0` to stay Swift 5.10-compatible. If you want the latest FluidAudio (0.12+), upgrade to Command Line Tools 16+ (`softwareupdate -i "Command Line Tools for Xcode-16.4"`) and bump the version in `Package.swift`.

**Have to re-add the app to Accessibility every time I rebuild.** macOS ties the Accessibility grant to the app's code signature. With ad-hoc signing each build gets a different signature, so the grant doesn't apply. Fix once: create a self-signed code-signing certificate via Keychain Access (`Certificate Assistant → Create a Certificate…`, name `VoicePTT Local`, type `Code Signing`, leave the override-defaults checkbox off). `build.sh` auto-detects this cert and uses it; subsequent rebuilds keep the same signature and the Accessibility grant sticks.

**`xcrun: error: unable to lookup item 'PlatformPath'`.** Cosmetic warning from `swift build`. The build still succeeds. Caused by the Command Line Tools not exposing the macOS platform path that XCTest expects. Safe to ignore.

**Recorded audio sounds clipped or muffled.** AVAudioEngine uses your **default input device**. Check System Settings → Sound → Input.

**App disk usage keeps growing.** When FluidAudio bumps its model version, the old version stays in the cache. Settings → Model storage → trash icon next to the stale entry, or "Clear all" (active model re-downloads on next launch).

---

## Development

```sh
# debug build (no codesign, no .app bundle)
swift build

# release build + .app bundle + codesign + auto-restart running app
./build.sh

# clean
swift package clean
rm -rf .build VoicePTT.app

# show resolved dependency versions
swift package show-dependencies
```

`build.sh` skips auto-restart when called by `release.sh` (controlled via `NO_RESTART=1`) so the in-app "Download & install" flow can be tested against the just-published release.

### Cutting a release

```sh
./release.sh 0.3.0 "Release notes go here, single line."
```

The script bumps `CFBundleShortVersionString` in `Info.plist`, commits + pushes, builds, packages a `.zip`, and uses `gh release create` to publish with the zip attached. Pre-flight: clean working tree + the tag must not exist yet. There's also a Claude Code skill at `.claude/skills/release/SKILL.md` documenting the same flow for AI-assisted releases.

### Generating the app icon

Re-run only when the design changes:

```sh
swift tools/make_icon.swift
```

Renders a 1024×1024 master (orange rounded square + white SF mic.fill) and resamples down to all iconset sizes, then `iconutil` packages into `Resources/AppIcon.icns` which is committed.

### Project layout

```
voice-ptt/
├── Package.swift                  # SwiftPM manifest, FluidAudio dependency
├── build.sh                       # swift build → .app bundle → codesign → auto-restart
├── release.sh                     # cut a versioned GitHub release
├── tools/make_icon.swift          # one-shot icon generator
├── Resources/
│   ├── Info.plist                 # bundle metadata, permission strings
│   └── AppIcon.icns               # generated by tools/make_icon.swift
├── .claude/skills/release/        # /release slash command for Claude Code
└── Sources/VoicePTT/
    ├── EntryPoint.swift           # @main, NSApplication setup
    ├── AppDelegate.swift          # State machine; wires every piece together
    ├── Settings.swift             # UserDefaults: trigger, mode, hotkey, launch-at-login
    ├── ModelInfo.swift            # Display name + expected size of the speech model
    ├── HotkeyManager.swift        # Carbon RegisterEventHotKey
    ├── RightCommandMonitor.swift  # NSEvent global flagsChanged → Right ⌘ alone
    ├── AudioRecorder.swift        # AVAudioEngine tap; copies buffer for downstream
    ├── Transcriber.swift          # FluidAudio AsrManager wrapper
    ├── Paster.swift               # NSPasteboard + CGEvent ⌘V autopaste
    ├── LoginItem.swift            # SMAppService.mainApp register/unregister
    ├── ModelStorage.swift         # Inspect + clear the FluidAudio model cache
    ├── UpdateChecker.swift        # GitHub Releases poll + Download & install
    ├── AppStatus.swift            # Observable: mic / accessibility / model state
    ├── PermissionsView.swift      # Status panel rendered in Settings
    ├── MenuBarController.swift    # NSStatusItem with state-aware icon
    ├── StatusHUD.swift            # Floating panel for launch / errors / updates
    ├── RecordingIndicator.swift   # Cursor-following red dot during recording
    └── SettingsWindow.swift       # SwiftUI Form, Trigger picker, all sections
```

### Useful one-liners

```sh
# stream app logs
log stream --predicate 'process == "VoicePTT"'

# inspect FluidAudio's public API after the first build
grep -rn 'public func' .build/checkouts/FluidAudio/Sources/FluidAudio/ASR/

# what model files are cached
ls -la "$HOME/Library/Application Support/FluidAudio/Models/"
```

---

## Credits

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Swift SDK that does the actual ASR. We're a thin UX wrapper around it.
- [NVIDIA Parakeet TDT](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — the speech-recognition model.
- Inspired by [Kesha Voice Kit](https://github.com/drakulavich/kesha-voice-kit) (Rust + same FluidAudio under the hood).

## License

MIT — see [`LICENSE`](LICENSE).
