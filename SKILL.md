---
name: disrupted-network
description: Persist .claude-session/ state to survive network drops; resume work in fresh sessions without re-explaining context.
disable-model-invocation: true
---

# Disrupted Network — Session Persistence Protocol

**Your sole job: make sure the work survives the connection dying.**

If you are here, the connection is alive. What you manage is what's on disk when it isn't.

## The fundamental limitation

**Only what's been written to disk before a drop survives.** If the connection dies mid-response, that response is gone — the user gets back the last checkpoint. Checkpoint aggressively and continuously; disk-first is the entire strategy.

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
├── SESSION_LINK.md     # URL of the most recent Claude session (for recovery reference)
└── scratch/            # Intermediate outputs, cached docs, downloaded wheels
```

### CONTEXT.md — the most critical file

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

## Ready offline
- [ ] Refactor extract_features() in src/pipeline.py

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
- Python / Node: [versions]

## Proxy
- Tool: [V2Ray / Xray / Psiphon / WARP / WireGuard / Sing-box / Hysteria2 / Shadowsocks]
- SOCKS5: [127.0.0.1:PORT]
- HTTP proxy: [127.0.0.1:PORT]
- Last confirmed working: [ISO timestamp]

## Connectivity
- Last probe: [ISO timestamp]
- Result: [CONNECTED / PROXY_DEGRADED / PROXY_DOWN / OFFLINE]
```

## Operating Procedures

### On Session Start

1. **Check for `.claude-session/`.** If it exists: read `CONTEXT.md`, then `TODO.md`, then `FAILED_ATTEMPTS.md`. Give the user a 2-3 line summary. Do not ask them to re-explain anything already in those files.

2. **Check `SESSION_LINK.md` for a prior session URL.** If the `url:` field is not `(not yet recorded)`, present it:
   > "There's a link to your previous Claude session: [URL] — open it in your browser to reference the conversation history, or just continue with the saved context."
   Then **overwrite `SESSION_LINK.md`** with the current session URL. The URL is appended to git commit messages as `https://claude.ai/code/session_<ID>`. If unavailable, write `(not available in this environment)`.

3. **If no session state exists:** create `.claude-session/` and populate `CONTEXT.md` and `TODO.md` from what the user tells you. Write the current session URL to `SESSION_LINK.md`.

4. **Ask about connection stability — not current state.** The connection is working or you wouldn't be here. Useful question: *"Is this a stable window, or are you in a choppy session? If unstable, I'll checkpoint more aggressively and finish each piece fully before starting the next."*

### During Work

5. **Checkpoint after every meaningful unit of work.** A function complete, a file done, a decision made — any point where losing context costs more than 2 minutes to reconstruct. Update `PROGRESS.md` and `CONTEXT.md` every time.

6. **Offline work first, network work batched.** When a connection window opens, work through "Needs connection" tasks top-to-bottom. Batch multiple `pip install` calls into one.

7. **When a network operation fails:** log immediately in `FAILED_ATTEMPTS.md` with the exact error. Move the task to "Needs connection" in `TODO.md`. Continue with offline work — never stall.

8. **Write to files, not terminal.** Terminal output is lost on disconnect. If it matters, it goes in a file.

### On Session End (or Suspected Drop)

9. **Write a full `CONTEXT.md` update.** The next session knows nothing. Be specific: exact file, line number, partial state, next step. E.g.: "Editing line 47 of `src/pipeline.py`, adding `normalize` to `process_batch()`. Signature updated, body not yet."

10. **Ensure `TODO.md` reflects reality.** Move completed items to Done. Update priorities.

11. **Append to `PROGRESS.md` and finalize `CONTEXT.md`.** Write the files directly — do not run `checkpoint.sh` (that's a user tool).

## User Tools

These scripts are deployed to `.claude-session/scripts/` by `init-session.sh`. **The user runs them — Claude does not run them autonomously.**

### netprobe.sh

Tests three layers: proxy port → local network (gateway + intranet) → foreign endpoints through proxy.

```bash
bash .claude-session/scripts/netprobe.sh 10808   # your SOCKS5 port
```

| Result | Meaning |
|--------|---------|
| CONNECTED | Proxy working, foreign reachable |
| PROXY_DEGRADED | Local up, proxy up, foreign blocked — DPI or remote server issue |
| PROXY_DOWN | Local up, proxy not running |
| OFFLINE | No internet access |

### checkpoint.sh

Manual checkpoint from a second terminal:

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
- **On suspected drop:** "Saving state now. If we get cut off, the next session resumes from here."
- **On network failure:** "Logged in FAILED_ATTEMPTS.md. Here's what I can do offline: [list]."
- **On ambiguity:** "Based on the session state, I think we were doing X — continue?" Never guess and run.

## Anti-Patterns

- **Don't run connectivity probes.** If you're here, the connection is working. Probes are the user's job.
- **Don't run `checkpoint.sh`.** Write the session files directly.
- **Don't retry failed network operations in a loop.** Log and move on.
- **Don't assume the next session is you.** Write `CONTEXT.md` for a stranger.
- **Don't leave state in terminal output.** Files only.
- **Don't checkpoint only at the end.** You may not get to the end.
- **Don't delete `FAILED_ATTEMPTS.md` entries.**
- **Don't ask the user to re-explain what's in the session files.** Read first.
