# Wisp

On-device dictation for macOS. Hold a key, say the thing, let go — the finished
text appears wherever your cursor already is, cleaned up and punctuated.

Nothing you say leaves the machine. There is no account, no telemetry, and no
network calls after the one-time model download.

## How it works

| Stage | Runs on |
|---|---|
| Capture | `AVAudioEngine`, 16 kHz mono |
| Recognition | Parakeet TDT v3 on the Neural Engine, via [FluidAudio](https://github.com/FluidInference/FluidAudio) |
| Cleanup | Apple Intelligence (`FoundationModels`), on-device |
| Insertion | Pasteboard, restored immediately afterwards |

## Dictate, or edit

Mode is decided by context rather than a command word. When you press the key,
Wisp reads the frontmost app's selection:

- **Nothing selected** — your words are dictated.
- **Something selected** — your words are an *instruction* for that text
  ("make this a bullet list", "cut it to two sentences"), and the selection is
  replaced. The capsule shows a pencil so this is never ambiguous.

## Requirements

- macOS 26 or later, Apple silicon
- Apple Intelligence enabled for the cleanup pass — dictation still works
  without it, falling back to a heuristic tidy
- ~600 MB on disk for the speech models, downloaded on first run

## Build

```bash
./Scripts/build.sh     # -> build/Wisp.app
./Scripts/package.sh   # -> dist/Wisp-0.1.0.pkg
```

Wisp needs **Microphone** and **Accessibility** permissions; the welcome screen
walks you through both. It lives in the menu bar with no Dock icon.

## Signing

Released builds are ad-hoc signed, not notarised, so macOS will refuse the
installer on first open — right-click and choose Open. See
[README-DISTRIBUTION.md](README-DISTRIBUTION.md) for what proper signing needs.

## Licence

MIT
