#!/bin/sh
# ═══════════════════════════════════════════════════════════════
# Schedule automation - designed to be called from crontab
# Usage: schedule.sh <device_id> <feature> <true|false> [name]
# Example in crontab:
#   0 6 * * * /root/iot-automation/schedule.sh esp01 relay true "Morning ON"
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

DEVICE_ID="$1"
FEATURE="$2"
STATE="$3"
NAME="${4:-schedule}"

if [ -z "$DEVICE_ID" ] || [ -z "$FEATURE" ] || [ -z "$STATE" ]; then
    echo "Usage: $0 <device_id> <feature> <true|false> [name]"
    exit 1
fi

log_msg "[SCHEDULE] '$NAME' fired: $DEVICE_ID/$FEATURE=$STATE"

"$SCRIPT_DIR/mqtt_cmd.sh" "$DEVICE_ID" "$FEATURE" "$STATE"
