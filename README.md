# Argus

[English](README.md) | [中文](README.zh.md)

Argus is a macOS menu-bar app that monitors **Claude Code** sessions in real time, displaying their status right below the MacBook notch.

Inspired by [VibeIsland](https://vibeisland.app/), but rebuilt from scratch with a different architecture and additional features (multi-session management, fine-grained task-state detection, iTerm2 tab jumping, etc.).

> **Why Argus?** In Greek mythology, Argus Panoptes was a giant with a hundred eyes, always watchful — even when he slept, some eyes stayed open. This app keeps a hundred metaphorical eyes on your AI agents, so you never miss when a task completes or needs attention.

---

## Features

- **Notch Pill** — Live capsule showing the number and state of running Claude Code sessions
- **Multi-Session Panel** — Expand to see all active sessions; click a row to jump to the corresponding iTerm2 tab
- **Task-Completion Alert** — Sound + green flash animation when a session transitions from Working to Idle
- **Auto Discovery** — No wrapper script needed; automatically scans `claude` processes and `~/.claude/projects/*.jsonl` logs
- **iTerm2 Jump** — Click a session row to activate iTerm2 and select the correct tab (matched by `tty` via AppleScript)

---

## Supported Platforms

| Terminal | Status |
|----------|--------|
| iTerm2   | ✅ Fully supported (AppleScript tab jump) |
| Others   | ⚠️ App activation only (no tab jump) |

| Agent | Status |
|-------|--------|
| Claude Code | ✅ Fully supported |
| Others | ❌ Not yet supported |

> **Current release supports iTerm2 + Claude Code only.** More terminals and agents are planned.

---

## Install

1. Download the latest [Release](https://github.com/opriz/argus/releases)
2. Drag `Argus.app` into `Applications`
3. First launch: **Right-click → Open** (not notarized)
4. Run `claude` in iTerm2 — Argus will detect it automatically

---

## Build from Source

```bash
git clone https://github.com/opriz/argus.git
cd argus
open Argus.xcodeproj
```

Requires Xcode 16+ and macOS 15+.

---

## License

MIT
