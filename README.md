# VoicePTT

Push-to-talk dictation for macOS. Press a hotkey (or hold Right ⌘), speak, release — your speech is transcribed and pasted into the active window. Runs entirely on-device on the Apple Neural Engine via [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet TDT).

Tested with English and Russian; 25 European languages supported by the model.

## Install

**Get the prebuilt app** from the [latest release](https://github.com/dmakhmutov/voice-ptt/releases/latest):

1. Download `VoicePTT-X.Y.zip`, unzip, drag `VoicePTT.app` to `/Applications`.
2. **Right-click → Open** the first time (Gatekeeper warning — self-signed cert, click Open).
3. Settings opens automatically. Grant **Microphone** + **Accessibility** via the Status panel buttons. Wait for the model (~500 MB, one-time download).
4. Press `⌘⇧Space`, dictate.

Future updates: **Settings → Updates → Check now → Download & install**.

**Or build from source:**

```sh
git clone git@github.com:dmakhmutov/voice-ptt.git
cd voice-ptt
./build.sh
```

Optional: create a self-signed `Code Signing` cert named `VoicePTT Local` in Keychain Access → Certificate Assistant. `build.sh` picks it up; without it, you'll re-grant Accessibility after every rebuild.

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1+) — Intel not supported (no ANE)
- ~1 GB free disk for the model
- Building from source: Swift 5.10+ (Command Line Tools 15+ enough; no full Xcode needed)

## Settings

Opens on every user-initiated launch (Alfred, Spotlight, Finder); auto-launch via login item stays silent. `Esc` closes it.

- **Status** — live state of permissions and model. Orange = needs attention, with deep-link buttons to System Settings.
- **Behavior** — Trigger (custom hotkey or hold Right ⌘ alone), mode (toggle / hold), Launch at login.
- **Test recording** — 3-second mic test, shows the recognized text right there.
- **Updates** — current version, check, one-click install.
- **Model storage** — list of cached models, per-entry trash, Clear all (active model re-downloads next launch).

## Behavior during a session

Cursor red dot pulses while recording. Auto-stop after 120 seconds. Transcript pastes into the focused window via clipboard + synthesized ⌘V; previous clipboard is restored ~0.3 s later.

## Troubleshooting

| Symptom | Fix |
|---|---|
| App launches, nothing visible | Menubar-only app — look for the mic icon top-right. Re-launch from Finder/Alfred to re-open Settings. |
| Hotkey does nothing | Settings → Status panel: grant whatever's orange. Then "Test recording" to confirm. |
| Text doesn't paste | Accessibility permission missing — grant it from the Status panel. |
| Have to re-grant Accessibility every rebuild | Create the `VoicePTT Local` self-signed cert (see Install). Stable signing → grant survives rebuilds. |
| `build.sh` fails: "incompatible tools version (6.0.0)" | Swift toolchain too old for current FluidAudio. The repo pins `0.7.0..<0.9.0` for Swift 5.10. Bump CLT (`softwareupdate -i "Command Line Tools for Xcode-16.4"`) and bump FluidAudio in `Package.swift` if you want newer. |
| `xcrun: error: 'PlatformPath'` | Cosmetic CLT warning, build still succeeds. Ignore. |
| Disk usage growing | Settings → Model storage → trash old entries. |

For verbose runtime logs:

```sh
log stream --predicate 'process == "VoicePTT"' --level debug
```

## Development

```sh
./build.sh                              # release build → .app → codesign → auto-restart running app
./release.sh 0.3.0 "Notes"              # bump version, push, package, gh release create
swift tools/make_icon.swift             # regenerate Resources/AppIcon.icns
```

Codebase is small and flat under `Sources/VoicePTT/`. Glance at `AppDelegate.swift` for the state machine; the rest are single-purpose helpers (Hotkey, AudioRecorder, Transcriber, UpdateChecker, etc.). FluidAudio's Swift SDK does all the heavy ASR lifting on the Neural Engine — we're a thin UX shell around it.

A `/release` Claude Code skill is at `.claude/skills/release/SKILL.md` for AI-assisted releases.

## Performance (M2/M3)

End-to-end "release hotkey → text appears" — about **0.5 seconds** for a 5-second utterance. Cold start (first launch, model loads into ANE) is 1–3 s; warm starts are sub-second.

## Credits

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Swift SDK doing the ASR.
- [NVIDIA Parakeet TDT](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — the model.
- Inspired by [Kesha Voice Kit](https://github.com/drakulavich/kesha-voice-kit).

## License

MIT — see [`LICENSE`](LICENSE).
