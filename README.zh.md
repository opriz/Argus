# Argus

[English](README.md) | [中文](README.zh.md)

Argus 是一个 macOS 菜单栏应用，为 **Claude Code** 等 AI Agent 提供实时状态监控与交互面板。

灵感来自 [VibeIsland](https://vibeisland.app/)，但完全独立实现，并扩展了多会话管理、细粒度任务状态检测、iTerm2 跳转等功能。

> **为什么叫 Argus？** 希腊神话中的百眼巨人阿耳戈斯（Argus Panoptes）全身长满眼睛，永不入眠——即使睡着时也有部分眼睛保持睁开。这个应用就像为你的 AI Agent 长出了无数只眼睛，让你不会错过任何一次任务完成或需要关注的状态变化。

---

## 功能

- **刘海胶囊状态栏** — 实时展示运行中的 Claude Code 会话数量与状态
- **多会话列表** — 展开面板查看所有进行中的会话，支持点击跳转到对应 iTerm2 Tab
- **任务完成提醒** — 会话从 Working 变为 Idle 时播放提示音 + 绿色闪光动画
- **自动检测** — 无需 wrapper 脚本，自动扫描 `claude` 进程与 `~/.claude/projects` 下的 jsonl 日志
- **iTerm2 跳转** — 点击会话行即可激活 iTerm2 并定位到对应 Tab（按 tty 匹配）

---

## 支持范围

| 终端 | 状态 |
|------|------|
| iTerm2 | ✅ 完整支持（AppleScript 跳转） |
| 其他终端 | ⚠️ 仅支持 App 激活（无法定位到具体 Tab） |

| Agent | 状态 |
|-------|------|
| Claude Code | ✅ 完整支持 |
| 其他 Agent | ❌ 暂未支持 |

> **当前版本仅支持 iTerm2 + Claude Code。** 后续计划扩展更多终端与 Agent。

---

## 安装

1. 下载最新 [Release](https://github.com/opriz/argus/releases)
2. 将 `Argus.app` 拖入 `Applications`
3. 首次打开需 **右键 → 打开**（未公证）
4. 在 iTerm2 中运行 `claude`，Argus 会自动检测

---

## 从源码构建

```bash
git clone https://github.com/opriz/argus.git
cd argus
open Argus.xcodeproj
```

需要 Xcode 16+，macOS 15+。

---

## 许可

MIT
