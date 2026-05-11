#!/bin/sh
# ═══════════════════════════════════════════════════════════════
# Countdown timer - execute command after N seconds
# Usage: countdown.sh <seconds> <device_id> <feature> <true|false>
# Example: countdown.sh 1800 esp01 relay false   # tắt relay sau 30 phút
# Run in background: countdown.sh 1800 esp01 relay false &
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

SECONDS_WAIT="$1"
DEVICE_ID="$2"
FEATURE="$3"
STATE="$4"

if [ -z "$SECONDS_WAIT" ] || [ -z "$DEVICE_ID" ] || [ -z "$FEATURE" ] || [ -z "$STATE" ]; then
    echo "Usage: $0 <seconds> <device_id> <feature> <true|false>"
    echo "Example: $0 1800 esp01 relay false"
    exit 1
fi

MINUTES=$((SECONDS_WAIT / 60))
log_msg "[COUNTDOWN] Started: $DEVICE_ID/$FEATURE=$STATE in ${MINUTES}m (${SECONDS_WAIT}s)"

# Write PID file for cancellation
PID_FILE="/tmp/countdown_${DEVICE_ID}_${FEATURE}.pid"
echo $$ > "$PID_FILE"

sleep "$SECONDS_WAIT"

log_msg "[COUNTDOWN] Executing: $DEVICE_ID/$FEATURE=$STATE"
"$SCRIPT_DIR/mqtt_cmd.sh" "$DEVICE_ID" "$FEATURE" "$STATE"

rm -f "$PID_FILE"
