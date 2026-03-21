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

## When it activates

Automatically when `.claude-session/` exists in your project root, or when you mention a proxy failure or network disruption. It does **not** trigger on general words like "resume", "checkpoint", or tool names — those cause too many false positives.

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

## DPI — when the proxy is up but `claude` still fails

DPI (Deep Packet Inspection) can block specific connections even when your VPN/proxy is running. See **`linux-macos.md` → DPI section** for:

- Protocol comparison (REALITY, Trojan, Hysteria2, VMess)
- TCP fragmentation with v2rayN
- Why setting `HTTPS_PROXY` already helps against DPI
- Cloudflare WARP as a fallback
- ECH (Encrypted Client Hello)

Short answer: **VLESS+REALITY** is the most DPI-resistant protocol available in v2rayN/Xray. **Hysteria2 over QUIC/UDP** is a strong alternative when TCP-based tunnels are throttled.

## Why the probe doesn't hit Google or PyPI directly

These endpoints are blocked. A direct probe returns failure regardless of whether your proxy works. `netprobe.sh` checks the proxy port first, then tests reachability through the proxy.

## Running the `claude` CLI through a proxy

### Linux / macOS

```bash
export HTTPS_PROXY="socks5h://127.0.0.1:10808"
export HTTP_PROXY="socks5h://127.0.0.1:10808"
claude
```

### Windows — v2rayN (without tunnel/TUN mode)

In PowerShell, set the proxy environment variables before running `claude`:

```powershell
$env:HTTP_PROXY = "http://127.0.0.1:10808"
$env:HTTPS_PROXY = "http://127.0.0.1:10808"
claude
```

Recent xray-core versions (shipped with v2rayN) accept HTTP CONNECT on the same port as SOCKS5, so 10808 usually works. If it doesn't, try port 10809 (v2rayN's dedicated HTTP inbound). Check **v2rayN → Settings → Inbounds** for your actual ports.

To make this permanent for your PowerShell session, add it to your profile (`$PROFILE`).

> Check **https://status.claude.ai** first if `claude` seems unresponsive — it may be a service outage rather than a local proxy issue.

## Platform support

Linux and macOS. See `linux-macos.md` for tool-specific setup, interface-based proxy detection (WireGuard, WARP), and system-wide proxy configuration. Windows notes are above.

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
