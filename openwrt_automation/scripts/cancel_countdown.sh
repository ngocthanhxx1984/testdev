#!/bin/sh
# ═══════════════════════════════════════════════════════════════
# Cancel a running countdown timer
# Usage: cancel_countdown.sh <device_id> <feature>
# Example: cancel_countdown.sh esp01 relay
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

DEVICE_ID="$1"
FEATURE="$2"

if [ -z "$DEVICE_ID" ] || [ -z "$FEATURE" ]; then
    echo "Usage: $0 <device_id> <feature>"
    exit 1
fi

PID_FILE="/tmp/countdown_${DEVICE_ID}_${FEATURE}.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        rm -f "$PID_FILE"
        log_msg "[COUNTDOWN] Cancelled timer for $DEVICE_ID/$FEATURE (PID=$PID)"
        echo "Countdown cancelled for $DEVICE_ID/$FEATURE"
    else
        rm -f "$PID_FILE"
        echo "No active countdown for $DEVICE_ID/$FEATURE"
    fi
else
    echo "No countdown found for $DEVICE_ID/$FEATURE"
fi
