# ECGBar

A macOS menubar app that turns Claude Code activity into a live ECG strip.

Each Claude Code hook fires a heartbeat into a scrolling waveform drawn inline in the menubar. When Claude finishes a turn and goes silent, the trace flatlines and the classic continuous ECG flatline tone plays — your "come verify the work" alarm.

## What you see

| Event class | Waveform | Sound | Color |
|---|---|---|---|
| Normal hooks (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SubagentStart/Stop`, `PreCompact`, `PostCompact`, `SessionStart`) | Full PQRST spike | 880 Hz blip | green |
| Long-running tool (no hook fires) | Soft "resting rate" filler beat every ~2 s | silent | green |
| Tool failure (`PostToolUseFailure`, `PermissionDenied`) | Inverted spike | 392 Hz low tone | green |
| Attention required (`Notification`, `PermissionRequest`) | Doublet (twin spike) | two-note chime | **purple, persistent** |
| `Stop` | Normal spike, then 3 s grace | blip | green → orange → red |
| `StopFailure` | Inverted spike, then 3 s grace | low tone | green → orange → red |
| 3 s after `Stop`/`StopFailure` with no further activity | Flat line | 2.5 s 1 kHz alarm | red → grey idle |
| `SessionEnd` | Normal spike, immediate flatline | blip + alarm | red → grey idle |

A 3-second debounce after `Stop` cancels the alarm if any new hook arrives — so multi-turn conversations don't keep firing the flatline.

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode toolchain or `xcode-select --install`)
- Claude Code

## Build & run

```bash
swift build -c release
./.build/release/ECGBar
```

The app installs itself as a status-bar accessory (no Dock icon) and listens on `127.0.0.1:7823`.

Click the menubar item for status, mute toggles, a manual test-beat trigger, and the hook-installation snippet.

## Wire it to Claude Code

Click the menubar item → **Install Claude Code hooks…** → **Copy**, then merge the snippet into `~/.claude/settings.json`.

The full snippet is also in [`docs/hooks-snippet.json`](docs/hooks-snippet.json). It covers 15 hook events:

```
SessionStart, SessionEnd, UserPromptSubmit,
PreToolUse, PostToolUse, PostToolUseFailure,
SubagentStart, SubagentStop,
Notification, PermissionRequest, PermissionDenied,
PreCompact, PostCompact,
Stop, StopFailure
```

Open a new Claude Code session after editing `settings.json` so the harness picks up the changes.

## Architecture

Single SwiftPM executable. Zero external dependencies.

| File | Role |
|---|---|
| `Sources/ECGBar/main.swift` | Entry point, sets `NSApp.setActivationPolicy(.accessory)` |
| `Sources/ECGBar/AppDelegate.swift` | `NSStatusItem`, menu, mute persistence, hooks-snippet panel |
| `Sources/ECGBar/ECGView.swift` | Custom `NSView` — ring buffer, PQRST template, 60 Hz redraw |
| `Sources/ECGBar/HeartbeatEngine.swift` | State machine (`idle`/`active`/`attention`/`armed`/`flatlining`), event-to-style routing, 2 s filler timer |
| `Sources/ECGBar/HookServer.swift` | `NWListener` on `127.0.0.1:7823` — `POST /heartbeat?e=…`, `POST /refresh` (back-compat), `GET /healthz` |
| `Sources/ECGBar/AudioPlayer.swift` | Synthesises PCM tones, writes to temp `.caf`, plays via `NSSound` (robust against system audio routing changes) |

Audio uses `NSSound` rather than `AVAudioEngine` so it survives output-device switches (e.g. when OBS or other recording tools change the system default output mid-session).

## Manual testing

```bash
# health check
curl http://127.0.0.1:7823/healthz

# fire any beat type
curl -X POST 'http://127.0.0.1:7823/heartbeat?e=PreToolUse'
curl -X POST 'http://127.0.0.1:7823/heartbeat?e=PostToolUseFailure'
curl -X POST 'http://127.0.0.1:7823/heartbeat?e=PermissionRequest'

# stop → 3 s armed → flatline alarm
curl -X POST 'http://127.0.0.1:7823/heartbeat?e=Stop'
```

## License

MIT.
