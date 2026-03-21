#!/usr/bin/env bash
# init-session.sh — Bootstrap .claude-session/ for Iranian disruption conditions
# Usage: bash /path/to/disrupted-network/scripts/init-session.sh [project_root]
#
# Creates the session directory structure, auto-detects proxy config,
# and populates ENVIRONMENT.md with current system state.
# Safe to re-run — will not overwrite CONTEXT.md, TODO.md, or PROGRESS.md.

set -euo pipefail

PROJECT_ROOT="${1:-.}"
SESSION_DIR="$PROJECT_ROOT/.claude-session"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$SESSION_DIR/scratch/docs"
mkdir -p "$SESSION_DIR/scripts"

# Copy helper scripts to session dir
SKILL_SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
for script in checkpoint.sh netprobe.sh; do
    if [ -f "$SKILL_SCRIPTS/$script" ] && [ ! -f "$SESSION_DIR/scripts/$script" ]; then
        cp "$SKILL_SCRIPTS/$script" "$SESSION_DIR/scripts/$script"
        chmod +x "$SESSION_DIR/scripts/$script"
    fi
done

# Template files — don't overwrite existing session state
if [ ! -f "$SESSION_DIR/CONTEXT.md" ]; then
    cat > "$SESSION_DIR/CONTEXT.md" << 'EOF'
# Session Context
Last updated: __TIMESTAMP__

## Objective
[TODO: What are we trying to accomplish?]

## Current State
[TODO: Where are we right now — exact file, function, step]

## Key Facts
- [TODO: Non-obvious things the next session needs]
- Proxy: [TODO: e.g., V2Ray SOCKS5 on 127.0.0.1:10808]

## Next Steps
1. [TODO: First action for the next session]

## Open Questions
- [TODO: Anything that needs user input]
EOF
    tmp=$(mktemp) && sed "s|__TIMESTAMP__|$TIMESTAMP|" "$SESSION_DIR/CONTEXT.md" > "$tmp" \
        && mv "$tmp" "$SESSION_DIR/CONTEXT.md"
fi

if [ ! -f "$SESSION_DIR/TODO.md" ]; then
    cat > "$SESSION_DIR/TODO.md" << 'EOF'
# TODO
Last updated: __TIMESTAMP__

## Needs connection (queue for next window)

## Ready offline

## Done
EOF
    tmp=$(mktemp) && sed "s|__TIMESTAMP__|$TIMESTAMP|" "$SESSION_DIR/TODO.md" > "$tmp" \
        && mv "$tmp" "$SESSION_DIR/TODO.md"
fi

if [ ! -f "$SESSION_DIR/PROGRESS.md" ]; then
    cat > "$SESSION_DIR/PROGRESS.md" << EOF
# Progress Log

## $TIMESTAMP
- Session initialized
EOF
fi

if [ ! -f "$SESSION_DIR/DECISIONS.md" ]; then
    printf "# Decisions\n" > "$SESSION_DIR/DECISIONS.md"
fi

if [ ! -f "$SESSION_DIR/FAILED_ATTEMPTS.md" ]; then
    printf "# Failed Attempts\n" > "$SESSION_DIR/FAILED_ATTEMPTS.md"
fi

# Auto-detect proxy (check common Iranian proxy ports)
detect_proxy() {
    local socks5_port="" http_port="" tool="Not detected"

    for port in 10808 1080 2080 40000; do
        if nc -z -w 1 127.0.0.1 "$port" 2>/dev/null; then
            socks5_port="$port"
            break
        fi
    done

    for port in 10809 8080 2081 8118; do
        if nc -z -w 1 127.0.0.1 "$port" 2>/dev/null; then
            http_port="$port"
            break
        fi
    done

    case "$socks5_port" in
        10808) tool="V2Ray/Xray" ;;
        40000) tool="Cloudflare WARP" ;;
        1080)  tool="Psiphon / Hysteria2 / Shadowsocks" ;;
        2080)  tool="Sing-box" ;;
        "")    tool="Not detected (no proxy running or port differs)" ;;
        *)     tool="Unknown tool (port $socks5_port)" ;;
    esac

    echo "tool=$tool|socks5=${socks5_port:-none}|http=${http_port:-none}"
}

PROXY_INFO=$(detect_proxy)
PROXY_TOOL=$(echo "$PROXY_INFO" | cut -d'|' -f1 | cut -d'=' -f2-)
PROXY_SOCKS5=$(echo "$PROXY_INFO" | cut -d'|' -f2 | cut -d'=' -f2)
PROXY_HTTP=$(echo "$PROXY_INFO" | cut -d'|' -f3 | cut -d'=' -f2)

if [ "$PROXY_SOCKS5" != "none" ]; then
    PROBE_CMD="bash .claude-session/scripts/netprobe.sh $PROXY_SOCKS5"
else
    PROBE_CMD="bash .claude-session/scripts/netprobe.sh"
fi

# Regenerate ENVIRONMENT.md (always reflects current state)
cat > "$SESSION_DIR/ENVIRONMENT.md" << EOF
# Environment
Generated: $TIMESTAMP

## System
$(uname -a 2>/dev/null || echo "unknown")

## Python
$(python3 --version 2>/dev/null || python --version 2>/dev/null || echo "not found")

## Node
$(node --version 2>/dev/null || echo "not found")

## Disk
$(df -h "$PROJECT_ROOT" 2>/dev/null | tail -1 || echo "unknown")

## Proxy (auto-detected)
- Tool: $PROXY_TOOL
- SOCKS5: $PROXY_SOCKS5
- HTTP: $PROXY_HTTP
- Note: use socks5h:// (not socks5://) in pip/curl to proxy DNS — critical in Iran

## Connectivity
- Run: $PROBE_CMD
- Run this to diagnose your current network state before starting a session

## Key Installed Python Packages
$({ pip list 2>/dev/null || pip3 list 2>/dev/null || echo "pip not available"; } | head -40)

## Project Root
$PROJECT_ROOT
EOF

# Ensure .claude-session/ is gitignored
if [ -d "$PROJECT_ROOT/.git" ]; then
    GITIGNORE="$PROJECT_ROOT/.gitignore"
    if ! grep -q "\.claude-session/" "$GITIGNORE" 2>/dev/null; then
        printf "\n# Claude session state (auto-generated)\n.claude-session/\n" >> "$GITIGNORE"
    fi
fi

echo ""
echo "Session initialized: $SESSION_DIR"
echo ""
if [ "$PROXY_SOCKS5" != "none" ]; then
    echo "Proxy detected: $PROXY_TOOL (SOCKS5 on $PROXY_SOCKS5)"
    echo "Next: bash $SESSION_DIR/scripts/netprobe.sh $PROXY_SOCKS5"
else
    echo "No proxy detected on common ports (10808, 1080, 2080, 40000)."
    echo "Start your proxy tool and re-run, or update ENVIRONMENT.md manually."
fi
