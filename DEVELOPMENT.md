# Development

Notes for hacking on VoicePTT or filing detailed bug reports. End-user docs are in the main [README](README.md).

## Build from source

```sh
git clone git@github.com:dmakhmutov/voice-ptt.git
cd voice-ptt
./rebuild.sh
```

`rebuild.sh` calls `build.sh` (which runs `swift build -c release`, packages a `.app` bundle, and codesigns) and then (re)launches the app. For just building without launching, use `./build.sh`.

**Optional but recommended:** create a self-signed code-signing certificate in Keychain Access → Certificate Assistant → Create a Certificate, name `VoicePTT Local`, type `Code Signing` (leave override-defaults off). `build.sh` auto-detects it. Without it, you'll re-grant Accessibility every rebuild because each ad-hoc signature has a different code identity.

**Toolchain:** Swift 5.10+. Command Line Tools alone are enough — full Xcode not required:

```sh
xcode-select --install
# or, for Swift 6 (needed if you bump FluidAudio to 0.9+):
softwareupdate -i "Command Line Tools for Xcode-16.4"
```

## Day-to-day commands

```sh
swift build                           # debug compile, no .app bundle
./rebuild.sh                          # release + .app + codesign + (re)launch
./build.sh                            # release + .app + codesign (no launch)
swift package clean                   # nuke .build/
swift tools/make_icon.swift           # regenerate Resources/AppIcon.icns
```

## Cutting a release

```sh
./release.sh 0.3.0 "Single-line release notes."
```

The script bumps `CFBundleShortVersionString` in `Info.plist`, commits + pushes, builds, packages a `.zip`, and uses `gh release create` to publish with the zip attached. Pre-flight: clean working tree, the tag must not already exist, the `gh` CLI must be authenticated.

There's also a Claude Code skill at `.claude/skills/release/SKILL.md` documenting the same flow for AI-assisted releases.

## Project layout

```
Sources/VoicePTT/
  EntryPoint.swift          — @main, NSApplication setup
  AppDelegate.swift         — state machine; wires every helper together
  Settings.swift            — UserDefaults: trigger, mode, hotkey, launch-at-login
  ModelInfo.swift           — display name + expected size of the speech model
  HotkeyManager.swift       — Carbon RegisterEventHotKey
  RightCommandMonitor.swift — NSEvent global flagsChanged → Right ⌘ alone detector
  AudioRecorder.swift       — AVAudioEngine tap; copies buffer for downstream
  Transcriber.swift         — FluidAudio AsrManager wrapper
  Paster.swift              — NSPasteboard + CGEvent ⌘V autopaste
  LoginItem.swift           — SMAppService.mainApp register/unregister
  ModelStorage.swift        — inspect + clear the FluidAudio model cache
  UpdateChecker.swift       — GitHub Releases poll + Download & install
  AppStatus.swift           — observable: mic / accessibility / model state
  PermissionsView.swift     — Status panel rendered in Settings
  MenuBarController.swift   — NSStatusItem with state-aware icon
  StatusHUD.swift           — floating panel for launch / errors / updates
  RecordingIndicator.swift  — cursor-following red dot during recording
  SettingsWindow.swift      — SwiftUI Form, Trigger picker, all sections
```

The codebase is small and flat. Start with `AppDelegate.swift`; the rest are single-purpose helpers.

## Troubleshooting

| Symptom | Fix |
|---|---|
| App launches, nothing visible | Menubar-only app — look for the mic icon top-right. Re-launch from Finder/Alfred to re-open Settings. |
| Hotkey does nothing | Settings → Status panel: grant whatever's orange. Then "Test recording" to confirm the pipeline. |
| Text doesn't paste | Accessibility permission missing — grant it from the Status panel. |
| Re-grant Accessibility every rebuild | Create the `VoicePTT Local` self-signed cert. Stable signing → grant survives rebuilds. |
| `build.sh` fails: "incompatible tools version (6.0.0)" | Swift toolchain too old. Bump CLT (`softwareupdate -i "Command Line Tools for Xcode-16.4"`) or pin FluidAudio to ≤0.8 in `Package.swift`. |
| `xcrun: error: 'PlatformPath'` warning | Cosmetic CLT warning, build still succeeds. Ignore. |
| Disk usage growing | Settings → Model storage → trash old entries. |
| Audio sounds clipped/muffled | AVAudioEngine uses the **default input device** — check System Settings → Sound → Input. |

For verbose runtime logs:

```sh
log stream --predicate 'process == "VoicePTT"' --level debug
```

Or open Console.app and filter by `VoicePTT`.

## How it works

```
Hotkey or Right ⌘   →   AppDelegate state machine   →   AVAudioEngine
                              ↓                              ↓
                        UI + indicators              FluidAudio (Parakeet on ANE)
                                                            ↓
                                                  NSPasteboard + CGEvent ⌘V
```

Around the recording pipeline: `StatusHUD` for launch progress, `RecordingIndicator` for the cursor red dot, `MenuBarController` for state icon, `UpdateChecker` for in-app updates, `AppStatus` for live permission state.

The whole thing is a thin Swift app around FluidAudio's Swift SDK. No Python, no Node, no FFI — just CoreML on the ANE.

## Useful one-liners

```sh
log stream --predicate 'process == "VoicePTT"'                                    # app logs
ls -la "$HOME/Library/Application Support/FluidAudio/Models/"                     # cached models
grep -rn 'public func' .build/checkouts/FluidAudio/Sources/FluidAudio/ASR/        # FluidAudio API
```
