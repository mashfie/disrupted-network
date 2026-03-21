#!/usr/bin/env bash
# netprobe.sh — Connectivity probe for Iranian network conditions
# Usage: bash .claude-session/scripts/netprobe.sh [SOCKS5_PORT]
#
# Tests in three layers:
#   1. Proxy port (no network required)
#   2. Iranian intranet endpoints directly (no proxy) — reachable even without VPN
#   3. Foreign endpoints through proxy — blocked by SHOMA without proxy
#
# Iranian intranet endpoints serve as ground truth: if they fail, you're fully offline.
# Foreign endpoints are tested only through the proxy — testing them directly is pointless.
#
# Requires: curl, nc (netcat)
# macOS: both built-in. Linux: apt install netcat-openbsd if nc is missing.

set -euo pipefail

SESSION_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SOCKS5_PORT="${1:-10808}"

command -v curl &>/dev/null || { echo "Error: curl not found" >&2; exit 1; }
command -v nc   &>/dev/null || { echo "Error: nc not found — install netcat-openbsd" >&2; exit 1; }

echo "=== Network Probe: $TIMESTAMP ==="
echo ""

# ── Layer 1: Proxy port (no network) ────────────────────────────────────────
SOCKS5_STATUS="NOT_LISTENING"
nc -z -w 2 127.0.0.1 "$SOCKS5_PORT" 2>/dev/null && SOCKS5_STATUS="LISTENING"
echo "Proxy (SOCKS5 :$SOCKS5_PORT): $SOCKS5_STATUS"
echo ""

# ── Layer 2: Iranian intranet (direct, no proxy) ────────────────────────────
# These are on Iran's national network — reachable even with no VPN/proxy.
# Use --noproxy '*' to bypass any https_proxy env var that might be set.
echo "Iranian intranet (direct — no proxy):"
test_intranet() {
    local name="$1" url="$2" code
    code=$(curl -s -m 6 -o /dev/null -w "%{http_code}" --noproxy '*' "$url" 2>/dev/null) \
        || code="TIMEOUT"
    [ "$code" = "000" ] && code="DNS_FAIL"
    echo "  $name: $code"
    echo "$code"
}

TMPDIR_PROBE=$(mktemp -d)
test_intranet "khamenei.ir"   "https://khamenei.ir"   > "$TMPDIR_PROBE/kh"   2>&1 &
test_intranet "snapp.ir"      "https://snapp.ir"       > "$TMPDIR_PROBE/sn"   2>&1 &
test_intranet "arvancloud.ir" "https://arvancloud.ir"  > "$TMPDIR_PROBE/ar"   2>&1 &
wait

# Extract only the last line (the status code) from each result file
KH_CODE=$(tail -1 "$TMPDIR_PROBE/kh")
SN_CODE=$(tail -1 "$TMPDIR_PROBE/sn")
AR_CODE=$(tail -1 "$TMPDIR_PROBE/ar")

# Print results (the echo in test_intranet already printed with indent)
# Re-check: test_intranet echoes the display line first, then the code. Let's reprint cleanly.
echo "  khamenei.ir:   $KH_CODE"
echo "  snapp.ir:      $SN_CODE"
echo "  arvancloud.ir: $AR_CODE"

INTRANET_UP=false
if echo "$KH_CODE $SN_CODE $AR_CODE" | grep -qE "^[23][0-9][0-9] |[23][0-9][0-9]$| [23][0-9][0-9] | [23][0-9][0-9]$"; then
    INTRANET_UP=true
fi
# Simpler check: any 2xx or 3xx code
for code in "$KH_CODE" "$SN_CODE" "$AR_CODE"; do
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
        local name="$1" url="$2" code
        code=$(curl -s -m 10 -o /dev/null -w "%{http_code}" \
            --socks5-hostname "127.0.0.1:$SOCKS5_PORT" "$url" 2>/dev/null) \
            || code="TIMEOUT"
        [ "$code" = "000" ] && code="CONNECT_FAIL"
        echo "  $name: $code"
        echo "$code"
    }

    test_via_proxy "PyPI"   "https://pypi.org/simple/"    > "$TMPDIR_PROBE/pypi" 2>&1 &
    test_via_proxy "GitHub" "https://github.com"          > "$TMPDIR_PROBE/gh"   2>&1 &
    test_via_proxy "npm"    "https://registry.npmjs.org/" > "$TMPDIR_PROBE/npm"  2>&1 &
    wait

    PY_CODE=$(tail -1 "$TMPDIR_PROBE/pypi")
    GH_CODE=$(tail -1 "$TMPDIR_PROBE/gh")
    NP_CODE=$(tail -1 "$TMPDIR_PROBE/npm")

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

rm -rf "$TMPDIR_PROBE"

# ── Determine status ─────────────────────────────────────────────────────────
if $FOREIGN_UP; then
    STATUS="CONNECTED"
    ADVICE="Proxy working. Run your network queue."
elif [ "$SOCKS5_STATUS" = "LISTENING" ] && $INTRANET_UP; then
    STATUS="PROXY_DEGRADED"
    ADVICE="Intranet up, proxy up, but foreign traffic blocked. DPI is active or remote server is unreachable. Work offline."
elif [ "$SOCKS5_STATUS" = "NOT_LISTENING" ] && $INTRANET_UP; then
    STATUS="PROXY_DOWN"
    ADVICE="Intranet up but proxy is not running. Start your proxy tool (V2Ray, Xray, Psiphon, etc.)."
elif ! $INTRANET_UP && [ "$SOCKS5_STATUS" = "LISTENING" ]; then
    STATUS="PROXY_DEGRADED"
    ADVICE="Proxy running but even intranet is unreachable. Full outage or severe throttling."
else
    STATUS="OFFLINE"
    ADVICE="No connectivity — not even intranet endpoints respond. Full outage or no internet."
fi

echo "Status: $STATUS"
echo "→ $ADVICE"

# ── Update ENVIRONMENT.md ─────────────────────────────────────────────────────
if [ -f "$SESSION_DIR/ENVIRONMENT.md" ]; then
    cat >> "$SESSION_DIR/ENVIRONMENT.md" << EOF

## Network Probe: $TIMESTAMP
- Status: $STATUS
- Proxy (:$SOCKS5_PORT): $SOCKS5_STATUS
- Intranet: $($INTRANET_UP && echo "reachable" || echo "unreachable")
- Foreign (via proxy): $($FOREIGN_UP && echo "reachable" || echo "blocked/skipped") $FOREIGN_DETAIL
EOF
fi
