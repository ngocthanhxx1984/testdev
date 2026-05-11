#!/bin/sh
# ═══════════════════════════════════════════════════════════════
# MQTT Broker Configuration for OpenWrt Automation
# ═══════════════════════════════════════════════════════════════

MQTT_HOST="127.0.0.1"
MQTT_PORT="1883"
MQTT_USER=""
MQTT_PASS=""

# Log file
LOG_FILE="/tmp/iot-automation.log"

# Build mosquitto_pub/sub auth flags
mqtt_auth_flags() {
    local flags="-h $MQTT_HOST -p $MQTT_PORT"
    [ -n "$MQTT_USER" ] && flags="$flags -u $MQTT_USER"
    [ -n "$MQTT_PASS" ] && flags="$flags -P $MQTT_PASS"
    echo "$flags"
}

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}
