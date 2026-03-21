---
name: disrupted-network-v1-archive
description: ARCHIVED — do not install. Historical v1 of the disrupted-network skill. Use SKILL.md instead.
---

> **ARCHIVED — v1.** This is the original version kept for reference only.
> Use `SKILL.md` (in the repo root) for the current version.
>
> Known issues in this version (fixed in current):
> - Step 3 instructs Claude to run `curl` directly to `pypi.org` without a proxy — exposes your
>   connection to DPI. The current version never probes foreign endpoints autonomously.
> - The trigger description is over-broad and fires on words like "continue" or "resume".
> - No proxy-awareness, no WireGuard/WARP guidance, no DPI documentation.

# Disrupted Network Resilience Protocol

You are operating under the assumption that your network connection is unreliable, expensive, or actively hostile. Any session may be severed at any moment. Your primary obligation is to **leave a usable trail** so the next session — which may be a completely fresh context window — can pick up the work without the user having to re-explain anything.

## The Core Rule

**Write first, execute second.** Before running any command that depends on the network, write your plan and current state to disk. Before doing anything complex, checkpoint. The disk is the only thing that survives between sessions.

## Session State Directory

All session persistence lives in `.claude-session/` at the project root. Create it immediately if it doesn't exist.

```
.claude-session/
├── CONTEXT.md          # What we're doing, why, and what we know
├── TODO.md             # Remaining tasks, ordered by priority
├── PROGRESS.md         # Completed steps with timestamps
├── DECISIONS.md        # Key decisions made and their rationale
├── FAILED_ATTEMPTS.md  # What went wrong (so the next session doesn't repeat it)
├── ENVIRONMENT.md      # Versions, paths, installed packages, system state
└── scratch/            # Intermediate outputs, partial results, downloaded files
```

### File Formats

**CONTEXT.md** — The most critical file. Written as a briefing for a fresh Claude session that knows nothing. Structure:

```markdown
# Session Context
Last updated: [ISO timestamp]

## Objective
[One paragraph: what the user wants to accomplish]

## Current State
[Where we are right now in the work. Be specific: which file, which function, which step.]

## Key Facts
- [Anything a fresh session needs to know that isn't obvious from the codebase]
- [User preferences, constraints, environment quirks]
- [Paths to important files]

## Next Steps
[Exactly what the next session should do first, second, third]

## Open Questions
[Anything unresolved that requires user input]
```

**TODO.md** — A flat, prioritized list. Each item should be actionable without additional context:

```markdown
# TODO
Last updated: [ISO timestamp]

## Blocked (needs network)
- [ ] pip install scipy  # needed for optimization module
- [ ] git push to remote

## Ready (can do offline)
- [ ] Refactor extract_features() in src/pipeline.py
- [ ] Write unit tests for the parser
- [ ] Draft the config schema

## Done
- [x] Set up project structure
- [x] Implemented CSV reader
```

**PROGRESS.md** — Append-only log:

```markdown
# Progress Log

## [ISO timestamp]
- Completed: [what]
- Method: [how]
- Output: [where the result lives on disk]
- Notes: [anything surprising or relevant]
```

**DECISIONS.md** — Why we chose X over Y, so the next session doesn't re-litigate:

```markdown
# Decisions

## [Short title]
- Date: [ISO timestamp]
- Choice: [what we decided]
- Reason: [why]
- Alternatives considered: [what we rejected and why]
```

**FAILED_ATTEMPTS.md** — Prevent loops:

```markdown
# Failed Attempts

## [Short description]
- Date: [ISO timestamp]
- What we tried: [specific command or approach]
- What happened: [error message, timeout, etc.]
- Why it failed: [diagnosis if known]
- Don't retry unless: [conditions that would make it worth trying again]
```

**ENVIRONMENT.md** — Pin the world:

```markdown
# Environment

## System
- OS: [uname -a output]
- Python: [version]
- Node: [version]
- Available disk: [df -h output]

## Installed Packages
[pip list / npm list output, or relevant subset]

## Network Status
- VPN: [working / down / intermittent]
- Last successful external request: [timestamp]
- Known blocked domains: [list]

## Project Paths
- Root: [path]
- Venv: [path]
- Data: [path]
```

## Operating Procedures

### On Session Start

1. **Check for `.claude-session/`**. If it exists, read `CONTEXT.md` first, then `TODO.md`, then `FAILED_ATTEMPTS.md`. Brief the user on where things stand — don't ask them to re-explain.
2. **If no session state exists**, create `.claude-session/` and populate `CONTEXT.md` and `TODO.md` from what the user tells you.
3. **Probe network health** before attempting anything that requires it:
   ```bash
   # Quick connectivity check — don't waste time on long timeouts
   timeout 3 curl -s -o /dev/null -w "%{http_code}" https://pypi.org/simple/ 2>/dev/null || echo "OFFLINE"
   ```
4. **Update ENVIRONMENT.md** with current system state.

### During Work

5. **Checkpoint after every meaningful unit of work.** A "meaningful unit" is: completing a function, finishing a file, making a design decision, or any point where losing context would cost more than 2 minutes to reconstruct. Update `PROGRESS.md` and `CONTEXT.md`.
6. **Separate network-dependent from network-independent tasks.** Do all offline work first. Batch network operations together for when a connection window opens.
7. **When a network operation fails:**
   - Log it in `FAILED_ATTEMPTS.md` immediately
   - Note the exact error (timeout, DNS, HTTP status, etc.)
   - Add the operation to `TODO.md` under "Blocked (needs network)"
   - **Continue with offline work** — never stall waiting for network
8. **Write code to files, not just to the terminal.** If you're drafting something, put it in a file. Terminal output evaporates; files persist.
9. **For pip/npm installs:** Check if the package is already installed before trying to download. Use `pip list | grep -i <pkg>` or `npm list <pkg>`. Cache downloaded wheels/tarballs in `.claude-session/scratch/` if possible.

### On Session End (or Suspected Imminent Drop)

10. **Write a comprehensive CONTEXT.md update.** Assume the next reader knows nothing about this session.
11. **Ensure TODO.md reflects reality.** Move completed items to Done, update priorities.
12. **If mid-task:** Write the partial state to a file, note in CONTEXT.md exactly where you stopped and what the next step is. Be pedantically specific: "I was editing line 47 of src/pipeline.py, adding the `normalize` parameter to `process_batch()`. The function signature is updated but the body hasn't been modified yet."

### Network Batching Strategy

When the network is intermittent, batch operations:

```markdown
## Network Queue (.claude-session/NETWORK_QUEUE.md)

### High Priority (do first when connection available)
- pip install pandas numpy  # needed for core work
- git pull origin main

### Medium Priority
- pip install pytest  # needed for tests but not blocking
- Fetch API docs from [url]

### Low Priority (nice to have)
- git push  # backup only
- pip install black  # formatting
```

When a network window opens, work through the queue top-to-bottom. Install multiple packages in a single `pip install` call. Clone/pull before pushing.

### Offline-First Development Patterns

- **Vendor dependencies when possible.** If you successfully install something, note the version in ENVIRONMENT.md so the next session doesn't need to re-download.
- **Copy documentation to disk.** If you fetch a man page, API reference, or Stack Overflow answer, save it to `.claude-session/scratch/docs/` — you or the next session may need it and the network may be gone.
- **Use standard library over third-party when feasible.** `json`, `csv`, `http.server`, `sqlite3`, `unittest` are all available without network. Prefer them unless the third-party library is already installed or genuinely irreplaceable.
- **Write self-contained scripts.** Minimize imports from packages that might not be available. If you must use an optional dependency, wrap it:
  ```python
  try:
      import pandas as pd
  except ImportError:
      pd = None
      # Fallback to csv module
  ```

### Deploy Checkpoint Script

At the start of any multi-step project, deploy this helper script so the user can manually trigger a checkpoint from another terminal, or so the agent can call it:

Run: `bash .claude-session/scripts/checkpoint.sh "description of what just happened"`

The script lives at `.claude-session/scripts/checkpoint.sh` — create it on first session init. See the bundled `scripts/checkpoint.sh` for the implementation.

## Communicating With the User

- **On resume:** Start with a 2-3 line summary of where things stand. Don't dump the entire context file at them. If something is blocked on network, say so.
- **On potential drop:** If you notice the user's messages are arriving slowly or you're getting network errors, proactively checkpoint and tell them: "I've saved state — if we get cut off, the next session can resume from here."
- **On ambiguity:** If the user says "continue" or "keep going" and the session state is stale or unclear, summarize what you *think* they want and confirm before proceeding. Don't guess and run.
- **Be blunt about what's blocked.** "I can't install X right now because the network is down. Here's what I can do without it: [list]. Want me to proceed with those?"

## Anti-Patterns (Don't Do These)

- **Don't retry network operations in a tight loop.** If it failed, log it and move on. The network comes back when it comes back.
- **Don't assume the next session is you.** Write context as if for a stranger. No "as we discussed" — there is no "we" across sessions.
- **Don't leave state only in terminal output.** If it matters, it goes in a file.
- **Don't ask the user to re-explain things that are in the session files.** Read before asking.
- **Don't checkpoint only at the end.** Checkpoint early and often. The whole point is that you might not get to the end.
- **Don't delete FAILED_ATTEMPTS.md entries.** They're there to prevent loops.
