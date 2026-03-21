---
name: disrupted-network
description: Session-persistence protocol for disrupted network conditions. Reads and maintains .claude-session/ state so a fresh Claude Code session can resume work immediately after a disconnection, without the user re-explaining anything.
disable-model-invocation: true
---

# Disrupted Network — Session Persistence Protocol

**Your sole job: make sure the work survives the connection dying.**

If you are here, the connection is alive. What you manage is what's on disk when it isn't.

## The fundamental limitation

**Only what's been written to disk before a drop survives.** If the connection dies while you are mid-response, that response is gone — the user gets back the last checkpoint. This is why you checkpoint aggressively and continuously, not just at the end. There is no way around this; disk-first is the entire strategy.

## Session State Directory

All persistence lives in `.claude-session/` at the project root. Create it at the start of every session if it doesn't exist.

```
.claude-session/
├── CONTEXT.md          # Briefing for a fresh session — the most critical file
├── TODO.md             # Tasks split by connectivity requirement
├── PROGRESS.md         # Append-only log of completed steps
├── DECISIONS.md        # What was decided and why
├── FAILED_ATTEMPTS.md  # What failed — prevents loops in future sessions
├── ENVIRONMENT.md      # System state, proxy config, last known connectivity
└── scratch/            # Intermediate outputs, cached docs, downloaded wheels
```

### CONTEXT.md — the most critical file

Written as a briefing for a session that knows nothing:

```markdown
# Session Context
Last updated: [ISO timestamp]

## Objective
[One paragraph: what we're building or fixing]

## Current State
[Exact file, function, step — specific enough for a fresh session to continue immediately]

## Key Facts
- [Non-obvious things the next session needs]
- [Proxy config if known: e.g., "V2Ray SOCKS5 on 127.0.0.1:10808"]
- [Important paths]

## Next Steps
1. [First thing to do]
2. [Then what]

## Open Questions
- [Anything that needs user input]
```

### TODO.md

```markdown
# TODO
Last updated: [ISO timestamp]

## Needs connection (queue for next window)
- [ ] pip install scipy
- [ ] git push origin main

## Ready offline
- [ ] Refactor extract_features() in src/pipeline.py
- [ ] Write tests for the parser

## Done
- [x] Set up project structure
```

### PROGRESS.md — append-only

```markdown
## [ISO timestamp]
- Completed: [what]
- Output: [where the result is]
- Notes: [anything surprising]
```

### FAILED_ATTEMPTS.md — prevents loops

```markdown
## [short description]
- Date: [ISO timestamp]
- Tried: [exact command or approach]
- Result: [timeout, TCP RST, HTTP 403, DNS NXDOMAIN, CONNECT_FAIL, etc.]
- Diagnosis: [DPI block? proxy down? foreign outage?]
- Retry if: [what would need to change]
```

### ENVIRONMENT.md

```markdown
# Environment
Generated: [timestamp]

## System
- OS: [Linux distro + kernel / macOS version]
- Python: [version]
- Node: [version]

## Proxy
- Tool: [V2Ray / Xray / Psiphon / WARP / WireGuard / Sing-box / Hysteria2 / Shadowsocks]
- SOCKS5: [127.0.0.1:PORT]
- HTTP proxy: [127.0.0.1:PORT]
- Last confirmed working: [ISO timestamp]

## Connectivity
- Last probe: [ISO timestamp — run by user via netprobe.sh]
- Result: [CONNECTED / PROXY_DEGRADED / PROXY_DOWN / OFFLINE]
- Note: probe only pings local gateway and intranet endpoints; all foreign checks go through proxy
```

## Operating Procedures

### On Session Start

1. **Check for `.claude-session/`.** If it exists: read `CONTEXT.md`, then `TODO.md`, then `FAILED_ATTEMPTS.md`. Give the user a 2-3 line summary of where things stand. Do not ask them to re-explain anything that's in those files.

2. **If no session state exists:** create `.claude-session/` and populate `CONTEXT.md` and `TODO.md` from what the user tells you.

3. **Ask about connection stability — not current state.** The connection is clearly working right now or you wouldn't be here. The useful question is: *"Is this a stable window, or are you in a choppy session? If unstable, I'll checkpoint more aggressively and finish each piece fully before starting the next."* Adjust the work plan accordingly.

### During Work

4. **Checkpoint after every meaningful unit of work.** Meaningful unit = a function complete, a file done, a decision made, or any point where losing context costs more than 2 minutes to reconstruct. Update `PROGRESS.md` and `CONTEXT.md` every time.

5. **Offline work first, network work batched.** When a connection window opens, work through "Needs connection" tasks top-to-bottom. Batch multiple `pip install` calls into one.

6. **When a network operation fails:** log immediately in `FAILED_ATTEMPTS.md` with the exact error (timeout? TCP RST? CONNECT_FAIL? DNS NXDOMAIN? HTTP 403?). Move the task to "Needs connection" in `TODO.md`. Continue with offline work — never stall.

7. **Write to files, not terminal.** Terminal output is lost on disconnect. If it matters, it goes in a file.

### On Session End (or Suspected Drop)

8. **Write a full `CONTEXT.md` update.** The next session knows nothing about this one. Be pedantically specific: exact file, line number, what the partial state is, what the next step is. "I was editing line 47 of `src/pipeline.py`, adding the `normalize` parameter to `process_batch()`. The function signature is updated but the body is not."

9. **Ensure `TODO.md` reflects reality.** Move completed items to Done. Update priorities.

10. **Append to `PROGRESS.md` and finalize `CONTEXT.md`.** Do not run `checkpoint.sh` — write the files directly. `checkpoint.sh` is a user tool for manual saves from a second terminal.

## User Tools

These scripts are deployed to `.claude-session/scripts/` by `init-session.sh`. **The user runs them from their terminal — Claude does not run them autonomously.**

### netprobe.sh

Run before starting a session, or after a failure. Tests three layers:

1. Proxy port (no network needed)
2. Local network: gateway ping (no external traffic) + intranet endpoints (`snapp.ir`, `arvancloud.ir`, `khamenei.ir`) directly without proxy — reachable for anyone in Iran without a VPN
3. Foreign endpoints through proxy (`pypi.org`, `github.com`, `registry.npmjs.org`) — only if proxy is up; **never tested without proxy**

```bash
bash .claude-session/scripts/netprobe.sh 10808   # your SOCKS5 port
```

| Result | Meaning |
|--------|---------|
| CONNECTED | Proxy working, foreign reachable |
| PROXY_DEGRADED | Local network up, proxy up, foreign blocked — DPI active or remote server unreachable |
| PROXY_DOWN | Local network up, proxy not running — start your proxy tool |
| OFFLINE | Gateway unreachable — full outage or no active interface |

### checkpoint.sh

Manual checkpoint from a second terminal if the connection seems unstable:

```bash
bash .claude-session/scripts/checkpoint.sh "description"
```

## Proxy-Aware Code Patterns

When writing code that makes network calls, surface the proxy config:

```python
import os, requests

proxies = {
    'http':  os.environ.get('http_proxy'),
    'https': os.environ.get('https_proxy'),
}
response = requests.get(url, proxies={k: v for k, v in proxies.items() if v})
```

```bash
# curl — use --socks5-hostname to proxy DNS too
curl --socks5-hostname 127.0.0.1:10808 https://example.com
```

## Proxy Port Defaults

| Tool | SOCKS5 | HTTP |
|------|--------|------|
| V2Ray / Xray | 10808 | 10809 |
| Psiphon | 1080 | 8080 |
| Sing-box | 2080 | 2081 |
| Hysteria2 / TUIC | 1080 | — |
| Cloudflare WARP | 40000 | — (or interface-based) |
| WireGuard | — (interface-based: wg0) | — |
| Shadowsocks | 1080 | — |

For interface-based tools (WireGuard, WARP), there is no SOCKS5 port — verify the network interface is up instead.

## Communication Guidelines

- **On resume:** 2-3 lines: what we were doing, where we stopped, what's next.
- **On suspected drop:** Checkpoint proactively — "Saving state now. If we get cut off, the next session resumes from here."
- **On network failure during work:** "Logged in FAILED_ATTEMPTS.md. Here's what I can do offline: [list]."
- **On ambiguity:** "Based on the session state, I think we were doing X — continue?" Never guess and run.

## Anti-Patterns

- **Don't run connectivity probes.** If you're here, the connection is working. Probes are the user's job.
- **Don't retry failed network operations in a loop.** Log and move on.
- **Don't assume the next session is you.** Write `CONTEXT.md` for a stranger.
- **Don't leave state in terminal output.** Files only.
- **Don't checkpoint only at the end.** You may not get to the end.
- **Don't delete `FAILED_ATTEMPTS.md` entries.**
- **Don't ask the user to re-explain what's in the session files.** Read first.
