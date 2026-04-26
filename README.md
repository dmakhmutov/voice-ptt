# VoicePTT

Push-to-talk transcription for macOS. Hotkey → record from mic → text pasted into the active window.

Stack: Swift + [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet TDT on the Apple Neural Engine). Supports English and Russian.

## Build

```sh
./build.sh
open VoicePTT.app
```

On first launch:
1. macOS will ask for microphone permission → allow.
2. For autopaste to work, grant the app **Accessibility** access: System Settings → Privacy & Security → Accessibility → add `VoicePTT.app`.
3. The Parakeet model (~2.5 GB) is downloaded on first run — be patient, progress is in the logs.

## Usage

- Default hotkey: `⌘⇧Space` (Cmd+Shift+Space).
- Default mode: **toggle** (press to start, press again to stop and transcribe).
- Alternative mode: **hold** (hold to record, release to transcribe).

Settings live in the menubar: mic icon → Settings…

## Development

```sh
swift build           # compile
swift run VoicePTT    # run without the .app wrapper (no LSUIElement, Dock icon shown)
```
