#!/bin/sh
# ═══════════════════════════════════════════════════════════════
# Send MQTT command to IoT device
# Usage: mqtt_cmd.sh <device_id> <feature> <true|false>
# Example: mqtt_cmd.sh esp01 relay true
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

DEVICE_ID="$1"
FEATURE="$2"
STATE="$3"

if [ -z "$DEVICE_ID" ] || [ -z "$FEATURE" ] || [ -z "$STATE" ]; then
    echo "Usage: $0 <device_id> <feature> <true|false>"
    echo "Example: $0 esp01 relay true"
    exit 1
fi

TOPIC="v1/devices/$DEVICE_ID/command"
PAYLOAD="{\"feature\":\"$FEATURE\",\"state\":$STATE}"

mosquitto_pub $(mqtt_auth_flags) -t "$TOPIC" -m "$PAYLOAD"

log_msg "[CMD] $DEVICE_ID/$FEATURE=$STATE"
