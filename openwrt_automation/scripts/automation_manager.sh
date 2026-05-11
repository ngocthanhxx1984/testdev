#!/bin/sh
# ═══════════════════════════════════════════════════════════════
# Automation Manager for OpenWrt
# Subscribes to MQTT topic 'home/automation/rules' to receive
# automation rules from the Flutter app, then automatically
# configures crontab and condition monitors.
#
# Also handles countdown requests from 'home/automation/countdown'.
#
# Usage: nohup /root/iot-automation/automation_manager.sh &
# Auto-start: add to /etc/rc.local or crontab @reboot
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

RULES_FILE="/tmp/iot_automation_rules.json"
CRON_TAG="# IOT_AUTO"
CONDITION_PIDS_DIR="/tmp/iot_conditions"

mkdir -p "$CONDITION_PIDS_DIR"

# ─── Kill all running condition monitors ─────────────────────
kill_condition_monitors() {
    # Kill by PID files
    for pidfile in "$CONDITION_PIDS_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            log_msg "[MANAGER] Killed condition monitor PID=$pid"
        fi
        rm -f "$pidfile"
    done
    # Kill any remaining condition_monitor processes (orphaned children)
    for pid in $(ps | grep '[c]ondition_monitor\.sh' | awk '{print $1}'); do
        kill "$pid" 2>/dev/null
    done
    sleep 1
    # Force kill any survivors
    for pid in $(ps | grep '[c]ondition_monitor\.sh' | awk '{print $1}'); do
        kill -9 "$pid" 2>/dev/null
    done
    # Clean up stale FIFOs
    rm -f /tmp/iot_cond_*.fifo
}

# ─── Parse operator from index to string ─────────────────────
operator_str() {
    case "$1" in
        0) echo "eq" ;;
        1) echo "neq" ;;
        2) echo "gt" ;;
        3) echo "lt" ;;
        4) echo "gte" ;;
        5) echo "lte" ;;
        *) echo "eq" ;;
    esac
}

# ─── Parse automation type from index ─────────────────────────
type_str() {
    case "$1" in
        0) echo "schedule" ;;
        1) echo "sunrise" ;;
        2) echo "sunset" ;;
        3) echo "countdown" ;;
        4) echo "condition" ;;
        *) echo "unknown" ;;
    esac
}

# ─── Apply rules from JSON ──────────────────────────────────
apply_rules() {
    local rules_json="$1"

    log_msg "[MANAGER] Applying automation rules..."

    # Kill existing condition monitors
    kill_condition_monitors

    # Remove old auto-generated cron entries
    crontab -l 2>/dev/null | grep -v "$CRON_TAG" > /tmp/cron_clean.tmp
    
    # Parse rules using jsonfilter (available on OpenWrt) or awk
    # We'll use a simple approach with sed/awk for maximum compatibility
    
    # Save rules to file
    echo "$rules_json" > "$RULES_FILE"

    # Count rules
    local count=$(echo "$rules_json" | grep -o '"id"' | wc -l)
    log_msg "[MANAGER] Processing $count rules"

    # Process each rule using awk
    # Extract individual rule objects
    echo "$rules_json" | awk '
    BEGIN { RS=""; FS="" }
    {
        # Split by rule boundaries
        n = split($0, chars, "")
        depth = 0
        in_rules = 0
        rule_start = 0
        rule_idx = 0
        
        for (i = 1; i <= n; i++) {
            if (chars[i] == "[" && !in_rules) {
                in_rules = 1
                continue
            }
            if (!in_rules) continue
            
            if (chars[i] == "{") {
                depth++
                if (depth == 1) rule_start = i
            }
            if (chars[i] == "}") {
                depth--
                if (depth == 0 && rule_start > 0) {
                    rule = ""
                    for (j = rule_start; j <= i; j++) {
                        rule = rule chars[j]
                    }
                    print rule
                    rule_start = 0
                    rule_idx++
                }
            }
        }
    }' | while read -r rule; do
        process_rule "$rule"
    done

    # Install updated crontab
    cat /tmp/cron_clean.tmp /tmp/cron_auto.tmp 2>/dev/null | crontab -
    rm -f /tmp/cron_clean.tmp /tmp/cron_auto.tmp

    log_msg "[MANAGER] Rules applied successfully"
}

# ─── Process a single rule ───────────────────────────────────
process_rule() {
    local rule="$1"

    # Extract fields using sed
    local id=$(echo "$rule" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
    local name=$(echo "$rule" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
    local type_idx=$(echo "$rule" | sed -n 's/.*"type":\([0-9]*\).*/\1/p')
    local enabled=$(echo "$rule" | sed -n 's/.*"enabled":\([a-z]*\).*/\1/p')
    local type=$(type_str "$type_idx")

    [ "$enabled" = "true" ] || return

    log_msg "[MANAGER] Processing rule: $name (type=$type, id=$id)"

    # Extract actions
    local actions_json=$(echo "$rule" | sed -n 's/.*"actions":\(\[.*\]\).*/\1/p')

    case "$type" in
        schedule)
            local hour=$(echo "$rule" | sed -n 's/.*"hour":\([0-9]*\).*/\1/p')
            local minute=$(echo "$rule" | sed -n 's/.*"minute":\([0-9]*\).*/\1/p')
            local repeat_days=$(echo "$rule" | sed -n 's/.*"repeatDays":\(\[[^]]*\]\).*/\1/p')

            [ -n "$hour" ] && [ -n "$minute" ] || return

            # Build cron day-of-week
            local cron_dow="*"
            if [ -n "$repeat_days" ] && [ "$repeat_days" != "[]" ]; then
                # Convert 0=Mon..6=Sun to cron 1=Mon..7=Sun
                cron_dow=$(echo "$repeat_days" | tr -d '[]' | awk -F, '{
                    for(i=1;i<=NF;i++) {
                        v=$i+1; if(v==8) v=0;
                        printf "%s%s", (i>1?",":""), v
                    }
                }')
            fi

            # Generate cron command for each action
            echo "$actions_json" | grep -o '{[^}]*}' | while read -r action; do
                local dev=$(echo "$action" | sed -n 's/.*"deviceId":"\([^"]*\)".*/\1/p')
                local feat=$(echo "$action" | sed -n 's/.*"feature":"\([^"]*\)".*/\1/p')
                local state=$(echo "$action" | sed -n 's/.*"state":\([a-z]*\).*/\1/p')

                echo "$minute $hour * * $cron_dow $SCRIPT_DIR/mqtt_cmd.sh $dev $feat $state && mosquitto_pub $(mqtt_auth_flags) -t home/automation/log -m '{\"id\":\"$id\",\"name\":\"$name\"}' $CRON_TAG" >> /tmp/cron_auto.tmp
            done
            ;;

        sunrise)
            echo "$actions_json" | grep -o '{[^}]*}' | while read -r action; do
                local dev=$(echo "$action" | sed -n 's/.*"deviceId":"\([^"]*\)".*/\1/p')
                local feat=$(echo "$action" | sed -n 's/.*"feature":"\([^"]*\)".*/\1/p')
                local state=$(echo "$action" | sed -n 's/.*"state":\([a-z]*\).*/\1/p')

                echo "0 6 * * * $SCRIPT_DIR/mqtt_cmd.sh $dev $feat $state && mosquitto_pub $(mqtt_auth_flags) -t home/automation/log -m '{\"id\":\"$id\",\"name\":\"$name\"}' $CRON_TAG" >> /tmp/cron_auto.tmp
            done
            ;;

        sunset)
            echo "$actions_json" | grep -o '{[^}]*}' | while read -r action; do
                local dev=$(echo "$action" | sed -n 's/.*"deviceId":"\([^"]*\)".*/\1/p')
                local feat=$(echo "$action" | sed -n 's/.*"feature":"\([^"]*\)".*/\1/p')
                local state=$(echo "$action" | sed -n 's/.*"state":\([a-z]*\).*/\1/p')

                echo "0 18 * * * $SCRIPT_DIR/mqtt_cmd.sh $dev $feat $state && mosquitto_pub $(mqtt_auth_flags) -t home/automation/log -m '{\"id\":\"$id\",\"name\":\"$name\"}' $CRON_TAG" >> /tmp/cron_auto.tmp
            done
            ;;

        condition)
            local src_dev=$(echo "$rule" | sed -n 's/.*"conditionDeviceId":"\([^"]*\)".*/\1/p')
            local src_feat=$(echo "$rule" | sed -n 's/.*"conditionFeature":"\([^"]*\)".*/\1/p')
            local op_idx=$(echo "$rule" | sed -n 's/.*"conditionOperator":\([0-9]*\).*/\1/p')
            local op=$(operator_str "$op_idx")

            # Get threshold value (numeric or boolean)
            local threshold=$(echo "$rule" | sed -n 's/.*"conditionValue":\([0-9.]*\).*/\1/p')
            local bool_val=$(echo "$rule" | sed -n 's/.*"conditionBoolValue":\([a-z]*\).*/\1/p')
            [ -z "$threshold" ] && threshold="$bool_val"

            [ -n "$src_dev" ] && [ -n "$src_feat" ] && [ -n "$threshold" ] || return

            # Start condition monitor for each action
            echo "$actions_json" | grep -o '{[^}]*}' | while read -r action; do
                local dev=$(echo "$action" | sed -n 's/.*"deviceId":"\([^"]*\)".*/\1/p')
                local feat=$(echo "$action" | sed -n 's/.*"feature":"\([^"]*\)".*/\1/p')
                local state=$(echo "$action" | sed -n 's/.*"state":\([a-z]*\).*/\1/p')

                "$SCRIPT_DIR/condition_monitor.sh" \
                    "$src_dev" "$src_feat" "$op" "$threshold" \
                    "$dev" "$feat" "$state" &

                local cpid=$!
                echo "$cpid" > "$CONDITION_PIDS_DIR/${id}_${dev}_${feat}.pid"
                log_msg "[MANAGER] Started condition monitor PID=$cpid for $name"
            done
            ;;

        countdown)
            # Countdown is handled on-demand via countdown topic
            log_msg "[MANAGER] Countdown rule '$name' registered (triggered via MQTT)"
            ;;
    esac
}

# ─── Handle countdown requests ───────────────────────────────
handle_countdown() {
    local payload="$1"

    local id=$(echo "$payload" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
    local action=$(echo "$payload" | sed -n 's/.*"action":"\([^"]*\)".*/\1/p')

    case "$action" in
        start)
            local seconds=$(echo "$payload" | sed -n 's/.*"seconds":\([0-9]*\).*/\1/p')
            local commands=$(echo "$payload" | sed -n 's/.*"commands":\(\[.*\]\).*/\1/p')

            # Kill existing countdown for this id
            local cpid_file="/tmp/countdown_$id.pid"
            if [ -f "$cpid_file" ]; then
                local old_pid=$(cat "$cpid_file")
                kill "$old_pid" 2>/dev/null
            fi

            # Start countdown in background
            (
                echo $$ > "$cpid_file"
                sleep "$seconds"

                # Execute all commands
                echo "$commands" | grep -o '{[^}]*}' | while read -r cmd; do
                    local dev=$(echo "$cmd" | sed -n 's/.*"deviceId":"\([^"]*\)".*/\1/p')
                    local feat=$(echo "$cmd" | sed -n 's/.*"feature":"\([^"]*\)".*/\1/p')
                    local state=$(echo "$cmd" | sed -n 's/.*"state":\([a-z]*\).*/\1/p')
                    "$SCRIPT_DIR/mqtt_cmd.sh" "$dev" "$feat" "$state"
                done

                # Notify app
                mosquitto_pub $(mqtt_auth_flags) -t "home/automation/log" \
                    -m "{\"id\":\"$id\",\"type\":\"countdown\"}"

                rm -f "$cpid_file"
                log_msg "[COUNTDOWN] Completed: $id"
            ) &

            log_msg "[COUNTDOWN] Started: $id for ${seconds}s"
            ;;

        stop)
            local cpid_file="/tmp/countdown_$id.pid"
            if [ -f "$cpid_file" ]; then
                local pid=$(cat "$cpid_file")
                kill "$pid" 2>/dev/null
                rm -f "$cpid_file"
                log_msg "[COUNTDOWN] Stopped: $id"
            fi
            ;;
    esac
}

# ─── Main: Subscribe to both topics ─────────────────────────
log_msg "[MANAGER] Starting automation manager..."

# Subscribe to rules topic (process retained message on start)
mosquitto_sub $(mqtt_auth_flags) -t "home/automation/rules" -t "home/automation/countdown" -v | while read -r line; do
    topic="${line%% *}"
    payload="${line#* }"

    case "$topic" in
        home/automation/rules)
            log_msg "[MANAGER] Received rules update"
            apply_rules "$payload"
            ;;
        home/automation/countdown)
            log_msg "[MANAGER] Received countdown request"
            handle_countdown "$payload"
            ;;
    esac
done
