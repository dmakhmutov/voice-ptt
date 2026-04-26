# VoicePTT

Push-to-talk dictation for macOS. Press a hotkey (or hold Right ⌘), speak, release — your speech is transcribed and pasted into the active window. Runs entirely on-device on the Apple Neural Engine via [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet TDT). No network, no API keys.

Tested with English and Russian; 25 European languages supported by the model.

## Install

Get the prebuilt app from the [latest release](https://github.com/dmakhmutov/voice-ptt/releases/latest):

1. Download `VoicePTT-X.Y.zip`, unzip, drag `VoicePTT.app` to `/Applications`.
2. **Right-click → Open** the first time (Gatekeeper warning — self-signed cert, click Open).
3. Settings opens automatically. Grant **Microphone** + **Accessibility** via the Status panel buttons. Wait for the model to download (~500 MB, one-time).
4. Press `⌘⇧Space`, dictate.

Future updates: **Settings → Updates → Check now → Download & install**.

### Or build from source

```sh
git clone git@github.com:dmakhmutov/voice-ptt.git
cd voice-ptt
./rebuild.sh
```

`rebuild.sh` builds, codesigns, and launches the app. For just building (no launch) use `./build.sh`.

Requires Swift 5.10+ (Command Line Tools 15+ — full Xcode not needed). For details, codesigning setup, and the dev workflow see [DEVELOPMENT.md](DEVELOPMENT.md).

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1+) — Intel not supported, no Neural Engine
- ~1 GB free disk for the model

## Behavior

Cursor red dot pulses while recording. Auto-stop after 120 seconds. Transcript pastes into the focused window via clipboard + synthesized ⌘V; previous clipboard is restored ~0.3 s later.

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

Building from source, troubleshooting, and contributor notes → [DEVELOPMENT.md](DEVELOPMENT.md).

## Credits

- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Swift SDK doing the ASR.
- [NVIDIA Parakeet TDT](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) — the model.
- Inspired by [Kesha Voice Kit](https://github.com/drakulavich/kesha-voice-kit).

## License

MIT — see [`LICENSE`](LICENSE).
