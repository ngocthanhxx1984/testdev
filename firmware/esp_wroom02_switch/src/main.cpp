// ═══════════════════════════════════════════════════════════════════════════
// ESP-WROOM-02 Smart Switch Firmware
// Controls LED (GPIO12) and Relay (GPIO15) via MQTT (no TLS)
// Physical switch/reset button on GPIO13
// Broker: OpenWrt Mosquitto at adangdang.ddns.net:443
// Features: WiFiManager provisioning, LittleFS config, OTA, factory reset,
//           power save mode (light sleep, 80MHz CPU, reduced TX power)
// ═══════════════════════════════════════════════════════════════════════════

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <WiFiManager.h>
#include <ESP8266httpUpdate.h>
#include <WiFiUdp.h>
#include <NTPClient.h>
#include "config.h"
#include "config_manager.h"
#include "mqtt_manager.h"
#include "web_server.h"

// ─── Global Objects ─────────────────────────────────────────────────────────
ConfigManager configMgr;
MqttManager   mqtt;
DeviceConfig  deviceCfg;
DeviceWebServer webServer;

// ─── NTP Time ───────────────────────────────────────────────────────────────
WiFiUDP ntpUDP;
NTPClient timeClient(ntpUDP, "pool.ntp.org", 7 * 3600, 60000); // UTC+7, update every 60s

// ─── Device State ───────────────────────────────────────────────────────────
bool relayState = false;
bool ledState   = false;

// ─── Button State Machine ───────────────────────────────────────────────────
bool     buttonPressed    = false;
unsigned long buttonDownTime = 0;
bool     longPressHandled = false;

// ─── WiFiManager Custom Parameters ─────────────────────────────────────────
WiFiManagerParameter* paramHost;
WiFiManagerParameter* paramPort;
WiFiManagerParameter* paramUser;
WiFiManagerParameter* paramPass;
WiFiManagerParameter* paramDeviceId;

// ─── Forward Declarations ───────────────────────────────────────────────────
void handleButton();
void toggleOutputs();
void factoryReset();
void startProvisioning();
void onMqttCommand(const char* feature, bool state);
void onOtaRequest(const char* url);
void applyOutputs();

// ═════════════════════════════════════════════════════════════════════════════
void setup() {
    Serial.begin(115200);
    Serial.println(F("\n\n=== ESP-WROOM-02 Smart Switch v" FW_VERSION " ==="));

    // Power save: reduce CPU frequency (80MHz vs 160MHz)
#if POWER_SAVE_ENABLED
    system_update_cpu_freq(CPU_FREQ_MHZ);
    Serial.printf_P(PSTR("[PWR] CPU freq: %dMHz\n"), CPU_FREQ_MHZ);
#endif

    // Initialize GPIO
    pinMode(PIN_RELAY, OUTPUT);
    pinMode(PIN_LED, OUTPUT);
    pinMode(PIN_BUTTON, INPUT_PULLUP);
    digitalWrite(PIN_RELAY, LOW);
    digitalWrite(PIN_LED, LOW);

    // Initialize LittleFS and load config
    configMgr.begin();

    if (configMgr.load(deviceCfg)) {
        Serial.println(F("[BOOT] Valid config found, connecting to WiFi..."));

        // Connect to WiFi using saved credentials
        WiFi.mode(WIFI_STA);
        WiFi.begin();

        Serial.print(F("[WIFI] Connecting"));
        int attempts = 0;
        while (WiFi.status() != WL_CONNECTED && attempts < 40) {
            delay(500);
            Serial.print('.');
            attempts++;
            // Check for factory reset during boot
            if (digitalRead(PIN_BUTTON) == LOW) {
                delay(LONG_PRESS_MS);
                if (digitalRead(PIN_BUTTON) == LOW) {
                    factoryReset();
                    return;
                }
            }
        }
        Serial.println();

        if (WiFi.status() == WL_CONNECTED) {
            Serial.printf_P(PSTR("[WIFI] Connected! IP: %s\n"), WiFi.localIP().toString().c_str());

            // Power save: WiFi light sleep + reduced TX power
#if POWER_SAVE_ENABLED
            WiFi.setSleepMode(WIFI_LIGHT_SLEEP);
            WiFi.setOutputPower(WIFI_TX_POWER_DBM);
            Serial.printf_P(PSTR("[PWR] WiFi light sleep, TX: %.1fdBm\n"), WIFI_TX_POWER_DBM);
#endif

            // Initialize NTP
            timeClient.begin();
            timeClient.update();
            Serial.printf_P(PSTR("[NTP] Time: %s\n"), timeClient.getFormattedTime().c_str());

            // Initialize MQTT
            mqtt.onCommand(onMqttCommand);
            mqtt.onOta(onOtaRequest);
            mqtt.begin(deviceCfg.mqttHost, deviceCfg.mqttPort,
                       deviceCfg.mqttUser, deviceCfg.mqttPass,
                       deviceCfg.deviceId);

            // Start web server
            webServer.begin(deviceCfg.deviceId, &relayState, &ledState);
        } else {
            Serial.println(F("[WIFI] Connection failed, entering provisioning mode"));
            startProvisioning();
        }
    } else {
        Serial.println(F("[BOOT] No valid config, entering provisioning mode"));
        startProvisioning();
    }
}

// ═════════════════════════════════════════════════════════════════════════════
void loop() {
    handleButton();
    mqtt.loop();
    timeClient.update();
    webServer.loop();

#if POWER_SAVE_ENABLED
    delay(LOOP_DELAY_MS);
#endif
}

// ─── Button Handler ─────────────────────────────────────────────────────────
void handleButton() {
    bool currentState = (digitalRead(PIN_BUTTON) == LOW);
    unsigned long now = millis();

    if (currentState && !buttonPressed) {
        // Button just pressed
        buttonPressed = true;
        buttonDownTime = now;
        longPressHandled = false;
    }

    if (currentState && buttonPressed) {
        // Button held down - check for long press
        if (!longPressHandled && (now - buttonDownTime >= LONG_PRESS_MS)) {
            longPressHandled = true;
            Serial.println(F("[BTN] Long press detected - Factory Reset!"));
            factoryReset();
        }
    }

    if (!currentState && buttonPressed) {
        // Button released
        if (!longPressHandled && (now - buttonDownTime >= DEBOUNCE_MS)) {
            // Short press - toggle relay and LED
            Serial.println(F("[BTN] Short press - toggling outputs"));
            toggleOutputs();
        }
        buttonPressed = false;
    }
}

// ─── Toggle Relay and LED ───────────────────────────────────────────────────
void toggleOutputs() {
    relayState = !relayState;
    ledState = !ledState;
    applyOutputs();
    mqtt.publishState(relayState, ledState);
}

// ─── Apply Output States to GPIO ────────────────────────────────────────────
void applyOutputs() {
    digitalWrite(PIN_RELAY, relayState ? HIGH : LOW);
    digitalWrite(PIN_LED, ledState ? HIGH : LOW);
}

// ─── Factory Reset ──────────────────────────────────────────────────────────
void factoryReset() {
    Serial.println(F("[RST] Factory reset initiated..."));

    // Blink LED rapidly to indicate reset
    for (int i = 0; i < 10; i++) {
        digitalWrite(PIN_LED, !digitalRead(PIN_LED));
        delay(100);
    }
    digitalWrite(PIN_LED, LOW);

    // Clear saved config
    configMgr.clear();

    // Clear WiFi credentials
    WiFi.disconnect(true);
    delay(500);

    Serial.println(F("[RST] Config cleared, restarting..."));
    ESP.restart();
}

// ─── WiFiManager Provisioning (Captive Portal) ─────────────────────────────
void startProvisioning() {
    WiFiManager wm;
    wm.setDebugOutput(false);

    // Custom parameters for MQTT configuration
    paramHost     = new WiFiManagerParameter("mqtt_host", "MQTT Broker Host", "adangdang.ddns.net", 128);
    paramPort     = new WiFiManagerParameter("mqtt_port", "MQTT Port", "443", 6);
    paramUser     = new WiFiManagerParameter("mqtt_user", "MQTT Username", "", 64);
    paramPass     = new WiFiManagerParameter("mqtt_pass", "MQTT Password", "", 64);
    paramDeviceId = new WiFiManagerParameter("device_id", "Device ID", "", 32);

    wm.addParameter(paramHost);
    wm.addParameter(paramPort);
    wm.addParameter(paramUser);
    wm.addParameter(paramPass);
    wm.addParameter(paramDeviceId);

    // Set timeout for portal (5 minutes)
    wm.setConfigPortalTimeout(300);

    // Set custom AP name
    wm.setAPStaticIPConfig(IPAddress(192, 168, 4, 1),
                           IPAddress(192, 168, 4, 1),
                           IPAddress(255, 255, 255, 0));

    Serial.println(F("[PROV] Starting captive portal..."));
    bool connected = wm.startConfigPortal(AP_NAME, AP_PASSWORD);

    if (connected) {
        Serial.println(F("[PROV] WiFi connected via portal"));

        // Save MQTT config to LittleFS
        strlcpy(deviceCfg.mqttHost, paramHost->getValue(), sizeof(deviceCfg.mqttHost));
        deviceCfg.mqttPort = atoi(paramPort->getValue());
        if (deviceCfg.mqttPort == 0) deviceCfg.mqttPort = MQTT_PORT_DEFAULT;
        strlcpy(deviceCfg.mqttUser, paramUser->getValue(), sizeof(deviceCfg.mqttUser));
        strlcpy(deviceCfg.mqttPass, paramPass->getValue(), sizeof(deviceCfg.mqttPass));
        strlcpy(deviceCfg.deviceId, paramDeviceId->getValue(), sizeof(deviceCfg.deviceId));
        deviceCfg.valid = true;

        configMgr.save(deviceCfg);

        // Initialize MQTT
        mqtt.onCommand(onMqttCommand);
        mqtt.onOta(onOtaRequest);
        mqtt.begin(deviceCfg.mqttHost, deviceCfg.mqttPort,
                   deviceCfg.mqttUser, deviceCfg.mqttPass,
                   deviceCfg.deviceId);

        // Start web server
        webServer.begin(deviceCfg.deviceId, &relayState, &ledState);
    } else {
        Serial.println(F("[PROV] Portal timed out, restarting..."));
        ESP.restart();
    }

    // Clean up
    delete paramHost;
    delete paramPort;
    delete paramUser;
    delete paramPass;
    delete paramDeviceId;
}

// ─── MQTT Command Handler ───────────────────────────────────────────────────
void onMqttCommand(const char* feature, bool state) {
    Serial.printf_P(PSTR("[CMD] Feature: %s, State: %s\n"), feature, state ? "ON" : "OFF");

    if (strcmp(feature, "relay") == 0) {
        relayState = state;
    } else if (strcmp(feature, "led") == 0) {
        ledState = state;
    } else {
        Serial.printf_P(PSTR("[CMD] Unknown feature: %s\n"), feature);
        return;
    }

    applyOutputs();
    mqtt.publishState(relayState, ledState);
}

// ─── OTA Update Handler ────────────────────────────────────────────────────
void onOtaRequest(const char* url) {
    Serial.printf_P(PSTR("[OTA] Starting update from: %s\n"), url);

    // Blink LED to indicate OTA in progress
    digitalWrite(PIN_LED, HIGH);

    WiFiClient otaClient;
    t_httpUpdate_return result = ESPhttpUpdate.update(otaClient, url);

    switch (result) {
        case HTTP_UPDATE_FAILED:
            Serial.printf_P(PSTR("[OTA] Update failed: %s\n"),
                          ESPhttpUpdate.getLastErrorString().c_str());
            digitalWrite(PIN_LED, LOW);
            break;
        case HTTP_UPDATE_NO_UPDATES:
            Serial.println(F("[OTA] No updates available"));
            digitalWrite(PIN_LED, LOW);
            break;
        case HTTP_UPDATE_OK:
            Serial.println(F("[OTA] Update successful, restarting..."));
            // Device will restart automatically
            break;
    }
}
