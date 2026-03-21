#!/usr/bin/env bash
# checkpoint.sh — Append a timestamped entry to PROGRESS.md and update CONTEXT.md
# Usage: bash .claude-session/scripts/checkpoint.sh "description of what just happened"
#
# USER-RUN TOOL. Run this from a second terminal if you think the connection is about
# to drop. Claude writes session files directly — it does not call this script.

set -euo pipefail

SESSION_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
DESCRIPTION="${1:-Manual checkpoint (no description provided)}"

# Ensure progress file exists with header (never truncate an existing file)
if [ ! -f "$SESSION_DIR/PROGRESS.md" ]; then
    printf "# Progress Log\n\n" > "$SESSION_DIR/PROGRESS.md"
fi

# Append checkpoint entry
cat >> "$SESSION_DIR/PROGRESS.md" << EOF

## $TIMESTAMP
- Checkpoint: $DESCRIPTION
EOF

echo "Checkpointed at $TIMESTAMP: $DESCRIPTION"

# Update the timestamp in CONTEXT.md if it exists
if [ -f "$SESSION_DIR/CONTEXT.md" ]; then
    tmp=$(mktemp)
    sed "s|^Last updated: .*|Last updated: $TIMESTAMP|" "$SESSION_DIR/CONTEXT.md" > "$tmp" \
        && mv "$tmp" "$SESSION_DIR/CONTEXT.md" \
        || rm -f "$tmp"
fi
