# disrupted-network

A Claude Code skill for working under Iranian internet disruption.

## What it does

When you're in Iran and Claude.ai gets cut off mid-session, this skill ensures your work context survives in `.claude-session/` on disk. A fresh session can resume immediately without you re-explaining anything.

**Primary feature:** Session persistence.
**Secondary feature:** Proxy-aware connectivity guidance — probes go through your proxy, not directly to blocked foreign endpoints.

## Install

```bash
claude skills install https://github.com/mashfie/disrupted-network
```

Or manually: copy `SKILL.md` into your Claude Code skills directory and reference it in `CLAUDE.md`.

## Trigger phrases

Claude Code activates this skill when you say:

- `resume`, `continue from last time`, `what were we doing`
- `save state`, `checkpoint`, `context lost`
- `the internet is down`, `VPN dropped`, `proxy failed`
- `V2Ray`, `Xray`, `Psiphon`, `WARP`, `WireGuard`, `Sing-box`, `Hysteria`
- `Iran`, `filtered`, `فیلتر`, `sanctions`, `disconnected`
- Or when `.claude-session/` exists in your project root

## Proxy tools supported

V2Ray / Xray / Psiphon / Cloudflare WARP / WireGuard / Sing-box / Hysteria2 / TUIC / Shadowsocks

## Quick start

Initialize session state at the start of a new project:

```bash
bash /path/to/disrupted-network/scripts/init-session.sh
```

This creates `.claude-session/` and auto-detects your running proxy.

Probe connectivity (only run when your proxy is running):

```bash
bash .claude-session/scripts/netprobe.sh 10808   # replace with your SOCKS5 port
```

Manual checkpoint (also callable by the agent):

```bash
bash .claude-session/scripts/checkpoint.sh "description of current state"
```

## Why the probe doesn't hit Google or PyPI directly

SHOMA blocks those endpoints. A direct probe from Iran returns failure regardless of whether your proxy works. `netprobe.sh` checks the proxy port first, then tests reachability through the proxy.

## Platform support

Linux and macOS. See `linux-macos.md` for tool-specific setup, interface-based proxy detection (WireGuard, WARP), and system-wide proxy configuration.

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Claude Code skill definition |
| `scripts/init-session.sh` | Bootstrap `.claude-session/` |
| `scripts/netprobe.sh` | Proxy-aware connectivity probe |
| `scripts/checkpoint.sh` | Timestamped progress checkpoint |
| `linux-macos.md` | Platform-specific proxy notes |
| `archive/` | Previous generic versions (v1, v2) |

## Versions

- **Current (`SKILL.md`)** — Iranian context, proxy-aware, session persistence as primary feature
- **`archive/v1-SKILL.md`** — Original generic version (session persistence only, no proxy awareness)
