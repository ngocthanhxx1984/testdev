#!/bin/sh
# ═══════════════════════════════════════════════════════════════
# Sunrise/Sunset automation
# Calculates approximate sunrise/sunset for Ho Chi Minh City (UTC+7)
# and schedules commands using 'at' or crontab
#
# Usage: sunrise_sunset.sh
# Add to crontab: 1 0 * * * /root/iot-automation/sunrise_sunset.sh
#
# Configuration: Edit the ACTIONS section below
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# ─── Location: Ho Chi Minh City ──────────────────────────────
# Approximate sunrise/sunset times (average for Vietnam)
# For more accuracy, use an API or calculate based on day of year
SUNRISE_HOUR=6
SUNRISE_MIN=0
SUNSET_HOUR=18
SUNSET_MIN=0

# ─── Sunrise Actions ────────────────────────────────────────
sunrise_actions() {
    log_msg "[SUNRISE] Executing sunrise automation at $SUNRISE_HOUR:$SUNRISE_MIN"
    # Add your sunrise commands here:
    "$SCRIPT_DIR/mqtt_cmd.sh" esp01 led false
    # "$SCRIPT_DIR/mqtt_cmd.sh" esp01 relay true
}

# ─── Sunset Actions ─────────────────────────────────────────
sunset_actions() {
    log_msg "[SUNSET] Executing sunset automation at $SUNSET_HOUR:$SUNSET_MIN"
    # Add your sunset commands here:
    "$SCRIPT_DIR/mqtt_cmd.sh" esp01 led true
    # "$SCRIPT_DIR/mqtt_cmd.sh" esp01 relay false
}

# ─── Schedule execution ─────────────────────────────────────
NOW_HOUR=$(date +%H)
NOW_MIN=$(date +%M)
NOW_TOTAL=$((NOW_HOUR * 60 + NOW_MIN))

SUNRISE_TOTAL=$((SUNRISE_HOUR * 60 + SUNRISE_MIN))
SUNSET_TOTAL=$((SUNSET_HOUR * 60 + SUNSET_MIN))

# If called before sunrise, schedule sunrise
if [ "$NOW_TOTAL" -le "$SUNRISE_TOTAL" ]; then
    DELAY=$(( (SUNRISE_TOTAL - NOW_TOTAL) * 60 ))
    log_msg "[SUNRISE] Scheduled in ${DELAY}s"
    (sleep "$DELAY" && sunrise_actions) &
fi

# If called before sunset, schedule sunset
if [ "$NOW_TOTAL" -le "$SUNSET_TOTAL" ]; then
    DELAY=$(( (SUNSET_TOTAL - NOW_TOTAL) * 60 ))
    log_msg "[SUNSET] Scheduled in ${DELAY}s"
    (sleep "$DELAY" && sunset_actions) &
fi

log_msg "[SUN] Sunrise=$SUNRISE_HOUR:$SUNRISE_MIN Sunset=$SUNSET_HOUR:$SUNSET_MIN scheduled"
