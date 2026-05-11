#ifndef CONFIG_H
#define CONFIG_H

// ─── GPIO Pin Definitions ───────────────────────────────────────────────────
#define PIN_RELAY   15  // GPIO15 - Relay control
#define PIN_LED     12  // GPIO12 - LED control
#define PIN_BUTTON   0  // GPIO0  - Flash button (built-in on most boards)

// ─── Button Timing ──────────────────────────────────────────────────────────
#define LONG_PRESS_MS       5000  // 5 seconds for factory reset
#define DEBOUNCE_MS          50   // Debounce time in ms

// ─── MQTT Settings ──────────────────────────────────────────────────────────
#define MQTT_PORT_DEFAULT    443
#define MQTT_RECONNECT_MS    5000
#define MQTT_QOS             1
#define DISCOVERY_INTERVAL  60000  // Re-broadcast discovery every 60s (was 30s)

// ─── Power Save Settings ────────────────────────────────────────────────────
// Similar to ESPHome power_save_mode: HIGH — trades 1-2s response latency
// for significantly lower power consumption and heat.
#define POWER_SAVE_ENABLED   1
#define LOOP_DELAY_MS       100   // Main loop delay (reduces CPU heat)
#define CPU_FREQ_MHZ         80   // 80MHz vs default 160MHz
#define WIFI_TX_POWER_DBM  10.0   // Reduce WiFi TX power (max 20.5)

// ─── MQTT Topics (templates, {id} replaced at runtime) ──────────────────────
#define TOPIC_DISCOVERY      "home/discovery"
#define TOPIC_CMD_TEMPLATE   "v1/devices/%s/command"
#define TOPIC_STATE_TEMPLATE "v1/devices/%s/state"
#define TOPIC_OTA_TEMPLATE   "v1/devices/%s/ota"
#define TOPIC_STATUS_TEMPLATE "v1/devices/%s/status"

// ─── Firmware Version ───────────────────────────────────────────────────────
#define FW_VERSION "1.1.0"

// ─── Config File Path (LittleFS) ────────────────────────────────────────────
#define CONFIG_FILE "/config.json"

// ─── WiFiManager AP Settings ────────────────────────────────────────────────
#define AP_NAME     "ESP8266-IoT-Setup"
#define AP_PASSWORD "12345678"

#endif // CONFIG_H
