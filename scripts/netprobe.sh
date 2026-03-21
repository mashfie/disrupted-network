#!/usr/bin/env bash
# netprobe.sh — Connectivity probe for restricted network conditions
# Usage: bash .claude-session/scripts/netprobe.sh [SOCKS5_PORT]
#
# USER-RUN TOOL ONLY. Claude does not call this script autonomously.
#
# Tests in three layers:
#   1. Proxy port (no network required)
#   2. Local network — default gateway ping (zero external traffic) +
#      Iranian intranet endpoints (direct, no proxy) to confirm national internet
#   3. Foreign endpoints through proxy only — never tested without proxy
#
# Requires: curl, nc (netcat), ping
# macOS: all built-in. Linux: apt install netcat-openbsd if nc is missing.

set -euo pipefail

SESSION_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SOCKS5_PORT="${1:-10808}"

command -v curl &>/dev/null || { echo "Error: curl not found" >&2; exit 1; }
command -v nc   &>/dev/null || { echo "Error: nc not found — install netcat-openbsd" >&2; exit 1; }

TMPDIR_PROBE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PROBE"' EXIT

echo "=== Network Probe: $TIMESTAMP ==="
echo ""

# ── Layer 1: Proxy port (no network) ────────────────────────────────────────
SOCKS5_STATUS="NOT_LISTENING"
nc -z -w 2 127.0.0.1 "$SOCKS5_PORT" 2>/dev/null && SOCKS5_STATUS="LISTENING"
echo "Proxy (SOCKS5 :$SOCKS5_PORT): $SOCKS5_STATUS"
echo ""

# ── Layer 2: Local network ───────────────────────────────────────────────────
LOCAL_UP=false
INTRANET_UP=false

# 2a. Gateway ping — instant, no DNS, no DPI. Tells you if the interface is alive.
GATEWAY=""
GATEWAY=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
if [ -z "$GATEWAY" ]; then
    GATEWAY=$(netstat -rn 2>/dev/null | awk '/^default/{print $2; exit}')
fi

# ping -W unit differs: Linux = seconds, macOS = milliseconds
PING_W=2
[ "$(uname -s)" = "Darwin" ] && PING_W=2000

echo "Local network:"
if [ -n "$GATEWAY" ]; then
    if ping -c 1 -W "$PING_W" "$GATEWAY" >/dev/null 2>&1; then
        LOCAL_UP=true
        echo "  Gateway ($GATEWAY): reachable"
    else
        echo "  Gateway ($GATEWAY): unreachable"
    fi
else
    echo "  No default gateway found (interface down?)"
fi

# 2b. Intranet endpoints — direct, no proxy. Reachable for anyone in Iran
# without a VPN. Use --noproxy to bypass any proxy env vars that may be set.
test_intranet() {
    local url="$1" code
    code=$(curl -s -m 6 -o /dev/null -w "%{http_code}" --noproxy '*' "$url" 2>/dev/null) \
        || code="UNREACHABLE"
    echo "$code"
}

test_intranet "https://snapp.ir"       > "$TMPDIR_PROBE/sn" &
test_intranet "https://arvancloud.ir"  > "$TMPDIR_PROBE/ar" &
test_intranet "https://khamenei.ir"    > "$TMPDIR_PROBE/kh" &
wait

SN_CODE=$(cat "$TMPDIR_PROBE/sn")
AR_CODE=$(cat "$TMPDIR_PROBE/ar")
KH_CODE=$(cat "$TMPDIR_PROBE/kh")

echo "  snapp.ir:      $SN_CODE"
echo "  arvancloud.ir: $AR_CODE"
echo "  khamenei.ir:   $KH_CODE"

for code in "$SN_CODE" "$AR_CODE" "$KH_CODE"; do
    if echo "$code" | grep -qE "^[23][0-9][0-9]$"; then
        INTRANET_UP=true
    fi
done

echo ""

# ── Layer 3: Foreign endpoints through proxy ────────────────────────────────
FOREIGN_UP=false
FOREIGN_DETAIL=""

if [ "$SOCKS5_STATUS" = "LISTENING" ]; then
    echo "Foreign endpoints (through proxy socks5h://127.0.0.1:$SOCKS5_PORT):"

    test_via_proxy() {
        local url="$1" code
        code=$(curl -s -m 10 -o /dev/null -w "%{http_code}" \
            --socks5-hostname "127.0.0.1:$SOCKS5_PORT" "$url" 2>/dev/null) \
            || code="CONNECT_FAIL"
        echo "$code"
    }

    test_via_proxy "https://pypi.org/simple/"    > "$TMPDIR_PROBE/pypi" &
    test_via_proxy "https://github.com"          > "$TMPDIR_PROBE/gh"   &
    test_via_proxy "https://registry.npmjs.org/" > "$TMPDIR_PROBE/npm"  &
    wait

    PY_CODE=$(cat "$TMPDIR_PROBE/pypi")
    GH_CODE=$(cat "$TMPDIR_PROBE/gh")
    NP_CODE=$(cat "$TMPDIR_PROBE/npm")

    echo "  PyPI:   $PY_CODE"
    echo "  GitHub: $GH_CODE"
    echo "  npm:    $NP_CODE"
    FOREIGN_DETAIL="PyPI:$PY_CODE GitHub:$GH_CODE npm:$NP_CODE"

    for code in "$PY_CODE" "$GH_CODE" "$NP_CODE"; do
        if echo "$code" | grep -qE "^[23][0-9][0-9]$"; then
            FOREIGN_UP=true
        fi
    done
    echo ""
fi

# ── Determine status ─────────────────────────────────────────────────────────
if $FOREIGN_UP; then
    STATUS="CONNECTED"
    ADVICE="Proxy working. Run your network queue."
elif [ "$SOCKS5_STATUS" = "LISTENING" ] && $INTRANET_UP; then
    STATUS="PROXY_DEGRADED"
    ADVICE="Intranet reachable, proxy up, foreign traffic blocked. DPI active or remote server unreachable. Work offline."
elif [ "$SOCKS5_STATUS" = "NOT_LISTENING" ] && $INTRANET_UP; then
    STATUS="PROXY_DOWN"
    ADVICE="Intranet up but proxy is not running. Start your proxy tool."
elif $LOCAL_UP && ! $INTRANET_UP && [ "$SOCKS5_STATUS" = "LISTENING" ]; then
    STATUS="PROXY_DEGRADED"
    ADVICE="Gateway up but even intranet is unreachable — full outage or severe throttling."
elif $LOCAL_UP && ! $INTRANET_UP && [ "$SOCKS5_STATUS" = "NOT_LISTENING" ]; then
    STATUS="OFFLINE"
    ADVICE="Gateway up but no internet connectivity and proxy not running — possible national outage."
else
    STATUS="OFFLINE"
    ADVICE="Gateway unreachable — full outage or no active network interface."
fi

echo "Status: $STATUS"
echo "→ $ADVICE"

# ── Update ENVIRONMENT.md ─────────────────────────────────────────────────────
if [ -f "$SESSION_DIR/ENVIRONMENT.md" ]; then
    cat >> "$SESSION_DIR/ENVIRONMENT.md" << EOF

## Network Probe: $TIMESTAMP
- Status: $STATUS
- Proxy (:$SOCKS5_PORT): $SOCKS5_STATUS
- Local (gateway): $($LOCAL_UP && echo "reachable" || echo "unreachable")
- Intranet: $($INTRANET_UP && echo "reachable" || echo "unreachable")
- Foreign (via proxy): $($FOREIGN_UP && echo "reachable" || echo "blocked/skipped")${FOREIGN_DETAIL:+ $FOREIGN_DETAIL}
EOF
fi
