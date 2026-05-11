// ═══════════════════════════════════════════════════════════════════════════
// ESP8266 + PIR — Motion Sensor Node
// Detects motion via PIR sensor on GPIO14, publishes to HiveMQ Cloud MQTT
// Also controls an LED on GPIO12 as motion indicator / alarm
// ═══════════════════════════════════════════════════════════════════════════

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <WiFiManager.h>
#include <LittleFS.h>
#include <ESP8266httpUpdate.h>
#include <ESP8266WebServer.h>
#include <ESP8266HTTPUpdateServer.h>

// ─── Configuration ──────────────────────────────────────────────────────────
#define FW_VERSION       "1.0.0"
#define CONFIG_FILE      "/config.json"
#define AP_NAME          "ESP8266-PIR-Setup"
#define AP_PASSWORD      "12345678"

#define PIN_PIR          14  // GPIO14 (D5) - PIR sensor output
#define PIN_LED          12  // GPIO12 (D6) - Motion indicator LED
#define PIN_BUTTON        0  // GPIO0 - Factory reset button

#define LONG_PRESS_MS    5000
#define MOTION_COOLDOWN  5000   // Min interval between motion events (ms)
#define DISCOVERY_INTERVAL 30000
#define MQTT_RECONNECT_MS  5000
#define STATE_INTERVAL   15000  // Publish full state every 15 seconds

// ─── Global Objects ─────────────────────────────────────────────────────────
WiFiClientSecure wifiClient;
PubSubClient     mqttClient(wifiClient);

char mqttHost[128] = "";
uint16_t mqttPort = 8883;
char mqttUser[64] = "";
char mqttPass[64] = "";
char deviceId[32] = "";

char topicState[64];
char topicStatus[64];
char topicOta[64];
char topicCmd[64];

// State
bool motionDetected = false;
bool ledEnabled     = true;   // Can be toggled via MQTT
unsigned long lastMotionTime  = 0;
unsigned long motionCount     = 0;
unsigned long lastDiscovery   = 0;
unsigned long lastReconnect   = 0;
unsigned long lastStatePub    = 0;

// Button
bool buttonPressed = false;
unsigned long buttonDownTime = 0;
bool longPressHandled = false;

// Web Server
ESP8266WebServer webServer(80);
ESP8266HTTPUpdateServer httpUpdater;

// ─── Config Management ──────────────────────────────────────────────────────
bool loadConfig() {
    if (!LittleFS.begin()) { LittleFS.format(); LittleFS.begin(); }
    File f = LittleFS.open(CONFIG_FILE, "r");
    if (!f) return false;
    JsonDocument doc;
    if (deserializeJson(doc, f)) { f.close(); return false; }
    f.close();
    strlcpy(mqttHost, doc["host"] | "", sizeof(mqttHost));
    mqttPort = doc["port"] | 8883;
    strlcpy(mqttUser, doc["user"] | "", sizeof(mqttUser));
    strlcpy(mqttPass, doc["pass"] | "", sizeof(mqttPass));
    strlcpy(deviceId, doc["device_id"] | "", sizeof(deviceId));
    return strlen(mqttHost) > 0 && strlen(deviceId) > 0;
}

void saveConfig() {
    JsonDocument doc;
    doc["host"] = mqttHost; doc["port"] = mqttPort;
    doc["user"] = mqttUser; doc["pass"] = mqttPass;
    doc["device_id"] = deviceId;
    File f = LittleFS.open(CONFIG_FILE, "w");
    if (f) { serializeJson(doc, f); f.close(); }
}

void clearConfig() {
    LittleFS.remove(CONFIG_FILE);
    WiFi.disconnect(true);
    delay(500);
    ESP.restart();
}

// ─── MQTT ───────────────────────────────────────────────────────────────────
void buildTopics() {
    snprintf(topicState,  sizeof(topicState),  "v1/devices/%s/state",   deviceId);
    snprintf(topicStatus, sizeof(topicStatus), "v1/devices/%s/status",  deviceId);
    snprintf(topicOta,    sizeof(topicOta),    "v1/devices/%s/ota",     deviceId);
    snprintf(topicCmd,    sizeof(topicCmd),    "v1/devices/%s/command", deviceId);
}

void publishDiscovery() {
    JsonDocument doc;
    doc["id"] = deviceId; doc["type"] = "esp8266_pir";
    doc["v"] = FW_VERSION;
    JsonArray feat = doc["features"].to<JsonArray>();
    feat.add("motion"); feat.add("led");
    char buf[256]; serializeJson(doc, buf, sizeof(buf));
    mqttClient.publish("home/discovery", buf, false);
}

void publishState() {
    JsonDocument doc;
    doc["id"] = deviceId;
    doc["motion"] = motionDetected;
    doc["led"] = ledEnabled;
    doc["motion_count"] = motionCount;
    doc["uptime"] = millis() / 1000;
    doc["rssi"] = WiFi.RSSI();
    char buf[256]; serializeJson(doc, buf, sizeof(buf));
    mqttClient.publish(topicState, buf, true);
}

void mqttCallback(char* topic, byte* payload, unsigned int len) {
    char json[512];
    memcpy(json, payload, min((unsigned int)511, len));
    json[min((unsigned int)511, len)] = '\0';

    JsonDocument doc;
    if (deserializeJson(doc, json)) return;

    if (strcmp(topic, topicCmd) == 0) {
        const char* feature = doc["feature"];
        if (feature && strcmp(feature, "led") == 0) {
            ledEnabled = doc["state"] | false;
            if (!ledEnabled) digitalWrite(PIN_LED, LOW);
            publishState();
        }
    }

    if (strcmp(topic, topicOta) == 0) {
        const char* cmd = doc["cmd"];
        const char* url = doc["url"];
        if (cmd && strcmp(cmd, "ota") == 0 && url) {
            WiFiClient otaClient;
            ESPhttpUpdate.update(otaClient, url);
        }
    }
}

void mqttConnect() {
    if (mqttClient.connected()) return;
    unsigned long now = millis();
    if (now - lastReconnect < MQTT_RECONNECT_MS) return;
    lastReconnect = now;

    char lwt[64];
    snprintf(lwt, sizeof(lwt), "{\"id\":\"%s\",\"status\":\"offline\"}", deviceId);

    if (mqttClient.connect(deviceId, mqttUser, mqttPass, topicStatus, 1, true, lwt)) {
        char online[64];
        snprintf(online, sizeof(online), "{\"id\":\"%s\",\"status\":\"online\"}", deviceId);
        mqttClient.publish(topicStatus, online, true);
        mqttClient.subscribe(topicOta, 1);
        mqttClient.subscribe(topicCmd, 1);
        publishDiscovery();
    }
}

// ─── Provisioning ───────────────────────────────────────────────────────────
void startProvisioning() {
    WiFiManager wm;
    WiFiManagerParameter pHost("host", "HiveMQ Hostname", "", 128);
    WiFiManagerParameter pPort("port", "MQTT Port", "8883", 6);
    WiFiManagerParameter pUser("user", "MQTT Username", "", 64);
    WiFiManagerParameter pPass("pass", "MQTT Password", "", 64);
    WiFiManagerParameter pId("id", "Device ID", "", 32);
    wm.addParameter(&pHost); wm.addParameter(&pPort);
    wm.addParameter(&pUser); wm.addParameter(&pPass);
    wm.addParameter(&pId);
    wm.setConfigPortalTimeout(300);

    if (wm.startConfigPortal(AP_NAME, AP_PASSWORD)) {
        strlcpy(mqttHost, pHost.getValue(), sizeof(mqttHost));
        mqttPort = atoi(pPort.getValue()); if (!mqttPort) mqttPort = 8883;
        strlcpy(mqttUser, pUser.getValue(), sizeof(mqttUser));
        strlcpy(mqttPass, pPass.getValue(), sizeof(mqttPass));
        strlcpy(deviceId, pId.getValue(), sizeof(deviceId));
        saveConfig();
    } else {
        ESP.restart();
    }
}

// ═════════════════════════════════════════════════════════════════════════════
void setup() {
    Serial.begin(115200);
    Serial.println("\n=== ESP8266 PIR Motion Sensor v" FW_VERSION " ===");

    pinMode(PIN_PIR, INPUT);
    pinMode(PIN_LED, OUTPUT);
    pinMode(PIN_BUTTON, INPUT_PULLUP);
    digitalWrite(PIN_LED, LOW);

    if (!loadConfig()) { startProvisioning(); }

    WiFi.mode(WIFI_STA); WiFi.begin();
    int tries = 0;
    while (WiFi.status() != WL_CONNECTED && tries++ < 40) delay(500);

    if (WiFi.status() != WL_CONNECTED) { startProvisioning(); return; }

    Serial.printf("[WIFI] IP: %s\n", WiFi.localIP().toString().c_str());

    buildTopics();
    wifiClient.setInsecure();
    mqttClient.setServer(mqttHost, mqttPort);
    mqttClient.setBufferSize(512);
    mqttClient.setCallback(mqttCallback);

    // Web server
    webServer.on("/", []() {
        unsigned long sec = millis() / 1000;
        unsigned long d = sec / 86400; sec %= 86400;
        unsigned long h = sec / 3600;  sec %= 3600;
        unsigned long m = sec / 60;    sec %= 60;
        String html = "<!DOCTYPE html><html><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<title>" + String(deviceId) + "</title>"
            "<style>body{font-family:sans-serif;margin:0;padding:20px;background:#f5f5f5}"
            ".card{background:#fff;border-radius:12px;padding:20px;margin:10px 0;box-shadow:0 2px 8px rgba(0,0,0,.1)}"
            "h1{color:#c62828;font-size:22px;margin:0 0 4px}.sub{color:#777;font-size:13px}"
            "table{width:100%;border-collapse:collapse;margin-top:10px}"
            "td{padding:8px 12px;border-bottom:1px solid #eee}td:first-child{font-weight:bold;color:#555;width:40%}"
            ".on{color:#c62828;font-weight:bold}.off{color:#2e7d32;font-weight:bold}"
            ".btn{display:inline-block;padding:12px 24px;background:#e65100;color:#fff;"
            "text-decoration:none;border-radius:8px;margin-top:16px;font-size:14px}"
            "</style></head><body>"
            "<div class='card'><h1>" + String(deviceId) + "</h1>"
            "<p class='sub'>ESP8266 PIR Motion Sensor &bull; v" FW_VERSION "</p></div>"
            "<div class='card'><table>"
            "<tr><td>Motion</td><td class='" + String(motionDetected ? "on'>DETECTED" : "off'>Clear") + "</td></tr>"
            "<tr><td>LED Indicator</td><td class='" + String(ledEnabled ? "on'>ON" : "off'>OFF") + "</td></tr>"
            "<tr><td>Motion Count</td><td>" + String(motionCount) + "</td></tr>"
            "<tr><td>WiFi RSSI</td><td>" + String(WiFi.RSSI()) + " dBm</td></tr>"
            "<tr><td>IP Address</td><td>" + WiFi.localIP().toString() + "</td></tr>"
            "<tr><td>Uptime</td><td>" + String(d) + "d " + String(h) + "h " + String(m) + "m " + String(sec) + "s</td></tr>"
            "</table></div>"
            "<a class='btn' href='/ota'>Firmware Update</a></body></html>";
        webServer.send(200, "text/html", html);
    });
    webServer.on("/ota", []() {
        String html = "<!DOCTYPE html><html><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width,initial-scale=1'>"
            "<title>OTA - " + String(deviceId) + "</title>"
            "<style>body{font-family:sans-serif;margin:0;padding:20px;background:#f5f5f5}"
            ".card{background:#fff;border-radius:12px;padding:20px;margin:10px 0;box-shadow:0 2px 8px rgba(0,0,0,.1)}"
            "h1{color:#e65100;font-size:20px}"
            ".btn{padding:12px 24px;background:#e65100;color:#fff;border:none;border-radius:8px;font-size:14px;cursor:pointer}"
            ".back{display:inline-block;margin-top:16px;color:#1565c0;text-decoration:none}"
            "</style></head><body><div class='card'><h1>Firmware Update</h1>"
            "<p>Current: v" FW_VERSION "</p>"
            "<form method='POST' action='/update' enctype='multipart/form-data'>"
            "<input type='file' name='update' accept='.bin'><br><br>"
            "<button type='submit' class='btn'>Upload &amp; Update</button></form></div>"
            "<a class='back' href='/'>&larr; Back</a></body></html>";
        webServer.send(200, "text/html", html);
    });
    httpUpdater.setup(&webServer, "/update");
    webServer.begin();
    Serial.printf("[WEB] http://%s/\n", WiFi.localIP().toString().c_str());
}

void loop() {
    // Button: long press = factory reset
    bool btn = (digitalRead(PIN_BUTTON) == LOW);
    if (btn && !buttonPressed) { buttonPressed = true; buttonDownTime = millis(); longPressHandled = false; }
    if (btn && buttonPressed && !longPressHandled && (millis() - buttonDownTime >= LONG_PRESS_MS)) {
        longPressHandled = true; clearConfig();
    }
    if (!btn && buttonPressed) buttonPressed = false;

    mqttConnect();
    mqttClient.loop();
    webServer.handleClient();

    unsigned long now = millis();

    // PIR motion detection
    bool pirState = digitalRead(PIN_PIR) == HIGH;
    if (pirState && !motionDetected && (now - lastMotionTime >= MOTION_COOLDOWN)) {
        motionDetected = true;
        motionCount++;
        lastMotionTime = now;
        Serial.printf("[PIR] Motion detected! Count: %lu\n", motionCount);
        if (ledEnabled) digitalWrite(PIN_LED, HIGH);
        publishState();
    } else if (!pirState && motionDetected) {
        motionDetected = false;
        digitalWrite(PIN_LED, LOW);
        publishState();
    }

    // Periodic state & discovery
    if (now - lastStatePub >= STATE_INTERVAL && mqttClient.connected()) {
        lastStatePub = now;
        publishState();
    }
    if (now - lastDiscovery >= DISCOVERY_INTERVAL && mqttClient.connected()) {
        lastDiscovery = now;
        publishDiscovery();
    }
}
