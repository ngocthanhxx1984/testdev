#!/bin/sh
# ═══════════════════════════════════════════════════════════════
# Condition-based automation monitor
# Subscribes to device state and triggers action when condition met
# Uses edge-trigger: only fires on false→true transition
#
# Usage: condition_monitor.sh <src_device> <src_feature> <operator> <value> \
#                              <dst_device> <dst_feature> <dst_state>
#
# Operators: gt, lt, gte, lte, eq, neq
#
# Examples:
#   # When temperature > 30 → turn on relay
#   condition_monitor.sh aht10_01 temperature gt 30 esp01 relay true
#
#   # When humidity < 40 → turn on LED
#   condition_monitor.sh aht10_01 humidity lt 40 esp01 led true
#
#   # When motion detected → turn on relay
#   condition_monitor.sh pir_01 motion eq true esp01 relay true
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

SRC_DEVICE="$1"
SRC_FEATURE="$2"
OPERATOR="$3"
THRESHOLD="$4"
DST_DEVICE="$5"
DST_FEATURE="$6"
DST_STATE="$7"

if [ -z "$DST_STATE" ]; then
    echo "Usage: $0 <src_device> <src_feature> <operator> <value> <dst_device> <dst_feature> <dst_state>"
    echo "Operators: gt, lt, gte, lte, eq, neq"
    exit 1
fi

TOPIC="v1/devices/$SRC_DEVICE/state"
CONDITION_MET=0

# Named FIFO for mosquitto_sub output (avoids orphaned pipe processes)
COND_FIFO="/tmp/iot_cond_$$.fifo"
SUB_PID=""

# Cleanup: kill mosquitto_sub child and remove FIFO on exit
cleanup() {
    [ -n "$SUB_PID" ] && kill "$SUB_PID" 2>/dev/null
    rm -f "$COND_FIFO"
    exit 0
}
trap cleanup TERM INT EXIT

log_msg "[CONDITION] Monitoring $SRC_DEVICE/$SRC_FEATURE $OPERATOR $THRESHOLD → $DST_DEVICE/$DST_FEATURE=$DST_STATE"

check_condition() {
    local current_value="$1"
    local result=0

    case "$OPERATOR" in
        gt)
            result=$(awk "BEGIN {print ($current_value > $THRESHOLD) ? 1 : 0}")
            ;;
        lt)
            result=$(awk "BEGIN {print ($current_value < $THRESHOLD) ? 1 : 0}")
            ;;
        gte)
            result=$(awk "BEGIN {print ($current_value >= $THRESHOLD) ? 1 : 0}")
            ;;
        lte)
            result=$(awk "BEGIN {print ($current_value <= $THRESHOLD) ? 1 : 0}")
            ;;
        eq)
            if [ "$current_value" = "$THRESHOLD" ]; then
                result=1
            fi
            ;;
        neq)
            if [ "$current_value" != "$THRESHOLD" ]; then
                result=1
            fi
            ;;
    esac

    echo "$result"
}

# Create FIFO and start mosquitto_sub in background
mkfifo "$COND_FIFO"
mosquitto_sub $(mqtt_auth_flags) -t "$TOPIC" -v > "$COND_FIFO" 2>/dev/null &
SUB_PID=$!

# Read from FIFO (single process, no orphan pipes)
while read -r line; do
    # Extract the payload (after topic name)
    payload="${line#* }"

    # Extract feature value using simple JSON parsing
    # For boolean: "motion":true → true
    # For numeric: "temperature":28.5 → 28.5
    current_value=$(echo "$payload" | sed -n "s/.*\"$SRC_FEATURE\":\([^,}]*\).*/\1/p")

    if [ -z "$current_value" ]; then
        continue
    fi

    is_met=$(check_condition "$current_value")

    # Edge trigger: only fire on 0→1 transition
    if [ "$is_met" = "1" ] && [ "$CONDITION_MET" = "0" ]; then
        log_msg "[CONDITION] Triggered! $SRC_DEVICE/$SRC_FEATURE=$current_value $OPERATOR $THRESHOLD → $DST_DEVICE/$DST_FEATURE=$DST_STATE"
        "$SCRIPT_DIR/mqtt_cmd.sh" "$DST_DEVICE" "$DST_FEATURE" "$DST_STATE"
    fi

    CONDITION_MET="$is_met"
done < "$COND_FIFO"
