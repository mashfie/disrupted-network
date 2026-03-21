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

**Only what's been written to disk before a drop survives.** If the connection dies while Claude is mid-response, that response is gone — you get back to the last checkpoint. This is why the skill checkpoints continuously throughout a session, not just at the end.

### What about tmux?

tmux keeps your **terminal session** alive across drops. This keeps **Claude's context** alive. When the Claude API connection dies, the server-side context window is gone regardless of tmux — the two problems are separate. tmux and this skill are complementary: tmux for the terminal, this for Claude's memory.

---

## Install

### Linux / macOS

**Step 1 — Put the skill where Claude Code can find it**

```bash
git clone https://github.com/mashfie/disrupted-network ~/.claude/skills/disrupted-network
```

No `CLAUDE.md` changes needed. Claude Code discovers skills automatically.

**Step 2 — Initialize session state in your project**

Run once per project (safe to re-run):

```bash
bash ~/.claude/skills/disrupted-network/scripts/init-session.sh
```

This creates `.claude-session/`, auto-detects your running proxy, and copies the helper scripts.

---

### Windows

The bash scripts require **WSL2** or **Git Bash** — they will not run in PowerShell or CMD.

See **`windows.md`** for the full Windows setup guide, including v2rayN configuration, WSL2 proxy routing, and common failures.

---

### Step 3 — Set up your proxy environment

Before running `claude`, set the proxy environment variables so Claude Code's API calls go through your VPN.

**Linux / macOS:**

```bash
export HTTPS_PROXY="socks5h://127.0.0.1:10808"
export HTTP_PROXY="socks5h://127.0.0.1:10808"
claude
```

**Windows — PowerShell (v2rayN, Windows-native `claude`):**

```powershell
$env:HTTPS_PROXY = "http://127.0.0.1:10809"
$env:HTTPS_PROXY = "http://127.0.0.1:10809"
claude
```

Port `10809` is v2rayN's HTTP inbound. PowerShell requires an HTTP proxy, not SOCKS5. See `windows.md` for WSL2 and Git Bash variants.

> To persist across terminals: add the `export` lines to `~/.bashrc` or `~/.zshrc` (Linux/macOS), or to your `$PROFILE` (PowerShell).

---

## Using the skill

### Trigger

Type `/disrupted-network` at the start of any Claude Code message:

```
/disrupted-network
```

Claude loads the skill. If `.claude-session/` exists, it reads the files and briefs you on where things stand. If not, it creates the session state and asks what you're working on. The skill **never auto-activates** — you control it with `/disrupted-network`.

### First session

```
/disrupted-network
Let's build a data pipeline that processes CSV files and outputs to SQLite.
My proxy is V2Ray SOCKS5 on 10808.
```

### Resuming after a drop

```
/disrupted-network
```

Claude reads `.claude-session/CONTEXT.md` and responds with something like:

> "We were refactoring `extract_features()` in `src/pipeline.py` — the function signature was updated but the body wasn't finished. `TODO.md` has two tasks queued for when you have a connection. Ready to continue?"

### Checking connectivity before a session

Run from your terminal (not from Claude):

```bash
bash .claude-session/scripts/netprobe.sh 10808   # your SOCKS5 port
```

| Result | Meaning |
|--------|---------|
| `CONNECTED` | Proxy working, foreign sites reachable |
| `PROXY_DEGRADED` | Proxy up but foreign traffic blocked — DPI or server issue |
| `PROXY_DOWN` | Local network up but proxy not running |
| `OFFLINE` | No internet — gateway unreachable or no external connectivity |

See `linux-macos.md` or `windows.md` for the full diagnostic flowchart.

### Manual checkpoint

If the session feels unstable, trigger a checkpoint from a second terminal:

```bash
bash .claude-session/scripts/checkpoint.sh "halfway through normalize() implementation"
```

---

## Files in this repo

| File | Purpose |
|------|---------|
| `SKILL.md` | The skill definition — loaded by Claude Code |
| `scripts/init-session.sh` | Bootstrap `.claude-session/` in a project |
| `scripts/netprobe.sh` | Connectivity probe (user runs this, not Claude) |
| `scripts/checkpoint.sh` | Timestamped progress checkpoint |
| `linux-macos.md` | Proxy setup, diagnostic flowchart, DPI guide (Linux & macOS) |
| `windows.md` | Full Windows guide — v2rayN, WSL2, Git Bash, common failures |
| `archive/v1-SKILL.md` | Original generic version (no proxy awareness) |

---

## Versions

- **Current (`SKILL.md`)** — Proxy-aware, session persistence, built for restricted network environments
- **`archive/v1-SKILL.md`** — Original generic version (session persistence only)
