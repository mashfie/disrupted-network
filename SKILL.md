---
name: disrupted-network
description: Session-persistence protocol for disrupted network conditions — filtering, DPI blocking, proxy failures, national outages. Primary purpose: maintain .claude-session/ state so a fresh session can resume without re-explanation after a disconnection. Claude's role is context persistence only; connectivity diagnostics are user-run tools. Trigger on: .claude-session/ exists in project root, proxy failed, proxy down, network disruption, فیلتر, فیلترشکن.
---

# Iranian Network Disruption — Session Persistence Protocol

You are operating in Iran. The SHOMA filtering system, DPI, and intermittent national outages mean Claude.ai sessions will be severed without warning. **Your sole obligation is to maintain session state so the next session can resume immediately, without the user re-explaining anything.**

**If the internet is down, you are not here.** This skill has no connectivity diagnostics for Claude to run — if you're active in a session, the connection is working. What you manage is what survives *after* a disconnection: the files on disk.

## Session State Directory

All session persistence lives in `.claude-session/` at the project root. Create it at the start of every session if it doesn't exist.

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

## Project Paths
- Root: [path]
- Venv: [path]
```

## Operating Procedures

### On Session Start

1. **Check for `.claude-session/`**. If it exists: read `CONTEXT.md`, then `TODO.md`, then `FAILED_ATTEMPTS.md`. Give the user a 2-3 line summary of where things stand. Do not ask them to re-explain.

2. **If no session state exists**: create `.claude-session/` and populate `CONTEXT.md` and `TODO.md` from what the user tells you. Ask for proxy config (tool + port) to record in `ENVIRONMENT.md`.

3. **Ask about connectivity state.** "Are you connected right now, or should we work offline?" Do not attempt to probe — connectivity diagnosis is the user's job (see User Tools below). Adjust the work plan based on the answer:
   - Connected: proceed normally, work through "Needs connection" tasks
   - Offline or uncertain: start with "Ready offline" tasks, queue the rest

### During Work

4. **Checkpoint after every meaningful unit of work.** "Meaningful unit" = a function complete, a file done, a decision made, or any point where losing context costs more than 2 minutes to reconstruct. Update `PROGRESS.md` and `CONTEXT.md`.

5. **Offline work first, network work batched.** When a connection window opens, work through the "Needs connection" queue top-to-bottom. Install multiple packages in a single `pip install` call.

6. **When a network operation fails:**
   - Log immediately in `FAILED_ATTEMPTS.md` with the exact error (timeout? TCP RST? CONNECT_FAIL? DNS NXDOMAIN? HTTP 403?)
   - Move the task to "Needs connection" in `TODO.md`
   - Continue with offline work — never stall

7. **Write to files, not terminal.** Terminal output is lost on disconnect.

8. **For the `claude` CLI through proxy (Linux/macOS):**
   ```bash
   # socks5h (not socks5) — proxy resolves DNS. Critical: DNS is poisoned.
   export https_proxy="socks5h://127.0.0.1:10808"
   export http_proxy="socks5h://127.0.0.1:10808"
   claude

   # Or using the HTTP proxy port (v2rayN default 10809):
   export HTTPS_PROXY="http://127.0.0.1:10809"
   export HTTP_PROXY="http://127.0.0.1:10809"
   claude
   ```

   **Windows (PowerShell) — v2rayN without system tunnel mode:**
   ```powershell
   $env:HTTP_PROXY = "http://127.0.0.1:10808"
   $env:HTTPS_PROXY = "http://127.0.0.1:10808"
   claude
   ```
   Port 10808 works as HTTP proxy in recent v2rayN/xray-core. If it doesn't work, try 10809 (the dedicated HTTP port). Check your v2rayN inbound settings for the actual port.

9. **For pip through proxy:**
   ```bash
   # socks5h (not socks5) — proxy resolves DNS.
   export https_proxy="socks5h://127.0.0.1:10808"
   export http_proxy="socks5h://127.0.0.1:10808"
   pip install package-name

   # Or per-command:
   pip install package-name --proxy socks5h://127.0.0.1:10808
   ```

10. **For git through proxy:**
    ```bash
    git config --global http.proxy "socks5://127.0.0.1:10808"
    # Unset when proxy is down:
    git config --global --unset http.proxy
    ```

### On Session End (or Suspected Drop)

10. **Write a full `CONTEXT.md` update.** The next session knows nothing about this one. Be pedantically specific: exact file, line number, what the partial state is, what the next step is. "I was editing line 47 of src/pipeline.py, adding the `normalize` parameter to `process_batch()`. The function signature is updated but the body is not."

11. **Ensure `TODO.md` reflects reality.** Move completed items to Done. Update priorities.

12. **Run checkpoint:**
    ```bash
    bash .claude-session/scripts/checkpoint.sh "description of current state"
    ```

## User Tools

These scripts are deployed to `.claude-session/scripts/` by `init-session.sh`. **The user runs them from their terminal — Claude does not run them autonomously.**

### init-session.sh

Bootstrap `.claude-session/` at the start of a new project. Auto-detects running proxy.

```bash
bash /path/to/disrupted-network/scripts/init-session.sh
```

### netprobe.sh

Run from your terminal to diagnose connectivity **before starting a Claude session**, or after a failure. Tests three layers:

1. Proxy port (no network needed)
2. Iranian intranet endpoints directly (`khamenei.ir`, `snapp.ir`, `arvancloud.ir`) — reachable without proxy; tells you if national internet exists
3. Foreign endpoints through proxy (`pypi.org`, `github.com`, `npmjs.org`) — only if proxy is up; never tested directly (blocked by SHOMA)

```bash
bash .claude-session/scripts/netprobe.sh 10808   # your SOCKS5 port
```

| Result | Meaning |
|--------|---------|
| CONNECTED | Proxy working, foreign reachable |
| PROXY_DEGRADED | Proxy up, intranet reachable, foreign blocked (DPI or server down) |
| PROXY_DOWN | Intranet reachable, proxy not running — start your proxy tool |
| OFFLINE | Even intranet unreachable — full outage |

### checkpoint.sh

Manual checkpoint from a second terminal if you think Claude is about to lose connection:

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

For interface-based tools (WireGuard, WARP), there is no SOCKS5 port — verify the network interface is up instead (see `linux-macos.md`).

## Communication Guidelines

- **On resume:** 2-3 lines: what we were doing, where we stopped, what's next.
- **On suspected drop:** Checkpoint proactively: "Saving state — the next session can resume from here."
- **On network failure during work:** "Logged in FAILED_ATTEMPTS.md. Here's what I can do offline: [list]."
- **On ambiguity:** "Based on the session state, I think we were doing X — continue?" Never guess and run.

## Anti-Patterns

- **Don't run connectivity probes.** If you're here, the connection to Claude.ai is working. If the internet is down, you're not here. Probes are the user's job.
- **Don't retry failed network operations in a loop.** Log and move on.
- **Don't assume the next session is you.** Write `CONTEXT.md` for a stranger.
- **Don't leave state in terminal output.** Files only.
- **Don't checkpoint only at the end.** You may not get to the end.
- **Don't delete `FAILED_ATTEMPTS.md` entries.**
- **Don't ask the user to re-explain what's in the session files.** Read first.
