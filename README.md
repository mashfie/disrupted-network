# disrupted-network

When your internet cuts out mid-session, Claude loses its context and you have to re-explain everything from scratch. This skill prevents that by saving work state to disk throughout the session, so a fresh session can resume immediately from where things stopped — without you re-explaining anything.

**This is a Claude Code (CLI) skill.** It does not work in the Claude.ai browser chat.

---

## How it works

Every session writes state into a `.claude-session/` directory in your project:

- `CONTEXT.md` — what you're building, exactly where things stand, what's next
- `TODO.md` — tasks split into "needs connection" and "ready offline"
- `PROGRESS.md` — append-only log of completed steps
- `FAILED_ATTEMPTS.md` — what failed and why, so the next session doesn't repeat it
- `ENVIRONMENT.md` — your proxy config and last known connectivity

When a new session starts and you invoke the skill, Claude reads those files and gives you a 2-3 line briefing. No re-explaining. You just continue.

### What gets saved and what doesn't

**Only what's been written to disk before a drop survives.** If the connection dies while Claude is mid-response, that response is gone — you get back to the last checkpoint. This is why the skill checkpoints continuously throughout a session, not just at the end. The disk is the only thing that survives between sessions.

---

## Install

### Step 1 — Put the skill where Claude Code can find it

**Global install** (available in all your projects — recommended):

```bash
mkdir -p ~/.claude/skills/disrupted-network
cp /path/to/disrupted-network/SKILL.md ~/.claude/skills/disrupted-network/SKILL.md
```

**Project-only install** (only available in this one project):

```bash
mkdir -p .claude/skills/disrupted-network
cp /path/to/disrupted-network/SKILL.md .claude/skills/disrupted-network/SKILL.md
```

You can clone the whole repo to get the scripts too:

```bash
git clone https://github.com/mashfie/disrupted-network ~/.claude/skills/disrupted-network
```

That's it. No `CLAUDE.md` changes needed. Claude Code discovers skills automatically from those directories.

### Step 2 — Initialize session state in your project

Run this once per project (safe to re-run):

```bash
bash ~/.claude/skills/disrupted-network/scripts/init-session.sh
```

This creates `.claude-session/` with all the template files, auto-detects your running proxy, and copies the helper scripts (`netprobe.sh`, `checkpoint.sh`) into `.claude-session/scripts/`.

> **Windows:** run this from WSL or Git Bash. The scripts require bash; they won't run in PowerShell or CMD.

### Step 3 — Set up your proxy environment

Before running `claude`, set the proxy environment variables so Claude Code's API calls go through your VPN.

**Linux / macOS:**

```bash
export HTTPS_PROXY="socks5h://127.0.0.1:10808"
export HTTP_PROXY="socks5h://127.0.0.1:10808"
claude
```

**Windows — PowerShell (v2rayN without TUN/tunnel mode):**

```powershell
$env:HTTP_PROXY = "http://127.0.0.1:10809"
$env:HTTPS_PROXY = "http://127.0.0.1:10809"
claude
```

Port `10809` is v2rayN's dedicated HTTP inbound (SOCKS5 is on `10808`; PowerShell's `HTTP_PROXY` requires an HTTP proxy, not SOCKS5). Check **v2rayN → Settings → Inbounds** for your actual ports. If you're still not sure, check `https://status.claude.ai` — it may be a service outage, not a proxy issue.

> To persist this across terminals, add the `export` lines to your `~/.bashrc` or `~/.zshrc` (Linux/macOS), or add the PowerShell lines to your `$PROFILE` (Windows).

---

## Using the skill

### The trigger

Type `/disrupted-network` at the start of any Claude Code message. That's it.

```
/disrupted-network
```

Claude Code will load the skill. If `.claude-session/` exists in your project, Claude reads it immediately and tells you where things stand. If it doesn't exist yet, Claude creates it and asks what you're working on.

The skill **never auto-activates.** You control it explicitly with `/disrupted-network`. This prevents it from firing when you don't want it.

### First session on a new project

```
/disrupted-network
Let's build a data pipeline that processes CSV files and outputs to SQLite.
My proxy is V2Ray SOCKS5 on 10808.
```

Claude creates the session state, records your proxy config, and starts working with checkpoints built in.

### Resuming after a disconnection

Just start Claude Code in the same project directory and run:

```
/disrupted-network
```

Claude reads `.claude-session/CONTEXT.md` and responds with something like:

> "We were refactoring `extract_features()` in `src/pipeline.py` — the function signature was updated to include the `normalize` parameter but the body wasn't finished yet. `TODO.md` has two tasks queued for when you have a connection. Ready to continue?"

You say yes. Work resumes.

### Checking connectivity before a session

Run the probe from your terminal (not from Claude) to understand your network state before starting:

```bash
bash .claude-session/scripts/netprobe.sh 10808   # your SOCKS5 port
```

| Result | Meaning |
|--------|---------|
| `CONNECTED` | Proxy working, foreign sites reachable — proceed normally |
| `PROXY_DEGRADED` | Proxy running but foreign traffic blocked — DPI or server issue, work offline |
| `PROXY_DOWN` | Local network up but proxy not running — start your proxy tool |
| `OFFLINE` | No gateway — full outage |

### Manual checkpoint from a second terminal

If you notice the session getting sluggish and think a drop is coming, you can trigger a checkpoint yourself:

```bash
bash .claude-session/scripts/checkpoint.sh "halfway through normalize() implementation"
```

---

## DPI — when the proxy is up but `claude` still fails

DPI (Deep Packet Inspection) can block specific connections even when your VPN is running. The TLS ClientHello to `api.anthropic.com` contains a plaintext SNI that DPI can read and block.

**Best protocols for DPI resistance** (strongest first):

| Protocol | Notes |
|----------|-------|
| VLESS + REALITY | Mimics real TLS to a legitimate domain — gold standard |
| Trojan + TLS | Looks like normal HTTPS |
| Hysteria2 / QUIC (UDP) | UDP-based; most DPI tools can't deep-inspect QUIC |
| VMess + WebSocket + TLS | Works through CDN fronting |
| Plain VMess / Shadowsocks | Easily fingerprinted — avoid |

**TCP fragmentation (v2rayN):** v2rayN has a Fragment feature that splits the TLS ClientHello into small segments, causing DPI engines to miss the SNI. Enable it in your Xray config:

```json
"sockopt": {
  "dialerProxy": "fragment",
  "fragment": { "packets": "tlshello", "length": "100-200", "interval": "10-20" }
}
```

**Why `HTTPS_PROXY` already helps:** When Claude Code uses `HTTPS_PROXY`, it sends a `CONNECT api.anthropic.com:443` request to your local proxy, which tunnels it through the VPN. The DPI at the ISP level only sees your VPN protocol — not the Anthropic SNI. Setting `HTTPS_PROXY` is not optional, it's the whole point.

See `linux-macos.md` for more detail on proxy tool setup and diagnosing `PROXY_DEGRADED`.

---

## Files in this repo

| File | Purpose |
|------|---------|
| `SKILL.md` | The skill definition — copy this to your skills directory |
| `scripts/init-session.sh` | Bootstrap `.claude-session/` in a project |
| `scripts/netprobe.sh` | Connectivity probe (user runs this, not Claude) |
| `scripts/checkpoint.sh` | Timestamped progress checkpoint |
| `linux-macos.md` | Proxy tool setup, DPI details, platform notes |
| `archive/v1-SKILL.md` | Original generic version (no proxy awareness) |

---

## Versions

- **Current (`SKILL.md`)** — Proxy-aware, session persistence, built for restricted network environments
- **`archive/v1-SKILL.md`** — Original generic version (session persistence only)
