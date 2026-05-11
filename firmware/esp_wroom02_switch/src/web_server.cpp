#include "web_server.h"

DeviceWebServer::DeviceWebServer() : _server(80), _deviceId(""), _relayState(nullptr), _ledState(nullptr) {}

void DeviceWebServer::begin(const char* deviceId, bool* relayState, bool* ledState) {
    _deviceId = deviceId;
    _relayState = relayState;
    _ledState = ledState;

    _server.on("/", [this]() { handleRoot(); });
    _server.on("/ota", [this]() { handleOtaPage(); });
    _httpUpdater.setup(&_server, "/update");
    _server.begin();
    Serial.printf_P(PSTR("[WEB] Server started on port 80 — http://%s/\n"), WiFi.localIP().toString().c_str());
}

void DeviceWebServer::loop() {
    _server.handleClient();
}

void DeviceWebServer::handleRoot() {
    unsigned long sec = millis() / 1000;
    unsigned long d = sec / 86400; sec %= 86400;
    unsigned long h = sec / 3600;  sec %= 3600;
    unsigned long m = sec / 60;    sec %= 60;

    _server.setContentLength(CONTENT_LENGTH_UNKNOWN);
    _server.send(200, F("text/html"), "");

    _server.sendContent_P(PSTR(
        "<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>"));
    _server.sendContent(_deviceId);
    _server.sendContent_P(PSTR(
        "</title><style>"
        "body{font-family:sans-serif;margin:0;padding:20px;background:#f5f5f5}"
        ".card{background:#fff;border-radius:12px;padding:20px;margin:10px 0;box-shadow:0 2px 8px rgba(0,0,0,.1)}"
        "h1{color:#1565c0;font-size:22px;margin:0 0 4px}"
        ".sub{color:#777;font-size:13px}"
        "table{width:100%;border-collapse:collapse;margin-top:10px}"
        "td{padding:8px 12px;border-bottom:1px solid #eee}"
        "td:first-child{font-weight:bold;color:#555;width:40%}"
        ".on{color:#2e7d32;font-weight:bold}"
        ".off{color:#c62828;font-weight:bold}"
        ".btn{display:inline-block;padding:12px 24px;background:#1565c0;color:#fff;"
        "text-decoration:none;border-radius:8px;margin-top:16px;font-size:14px}"
        ".btn:hover{background:#0d47a1}"
        "</style></head><body><div class='card'><h1>"));
    _server.sendContent(_deviceId);
    _server.sendContent_P(PSTR(
        "</h1><p class='sub'>ESP8266 Relay/LED Controller &bull; v" FW_VERSION "</p>"
        "</div><div class='card'><table>"
        "<tr><td>Relay</td><td class='"));
    _server.sendContent_P(_relayState && *_relayState ? PSTR("on'>ON") : PSTR("off'>OFF"));
    _server.sendContent_P(PSTR("</td></tr><tr><td>LED</td><td class='"));
    _server.sendContent_P(_ledState && *_ledState ? PSTR("on'>ON") : PSTR("off'>OFF"));
    _server.sendContent_P(PSTR("</td></tr><tr><td>WiFi RSSI</td><td>"));

    char buf[16];
    snprintf(buf, sizeof(buf), "%d", WiFi.RSSI());
    _server.sendContent(buf);

    _server.sendContent_P(PSTR(" dBm</td></tr><tr><td>IP Address</td><td>"));
    _server.sendContent(WiFi.localIP().toString());
    _server.sendContent_P(PSTR("</td></tr><tr><td>Free Heap</td><td>"));

    snprintf(buf, sizeof(buf), "%u", ESP.getFreeHeap());
    _server.sendContent(buf);

    _server.sendContent_P(PSTR(" bytes</td></tr><tr><td>Uptime</td><td>"));

    char uptime[32];
    snprintf(uptime, sizeof(uptime), "%lud %luh %lum %lus", d, h, m, sec);
    _server.sendContent(uptime);

    _server.sendContent_P(PSTR(
        "</td></tr></table></div>"
        "<a class='btn' href='/ota'>Firmware Update</a>"
        "</body></html>"));
    _server.sendContent("");
}

void DeviceWebServer::handleOtaPage() {
    _server.setContentLength(CONTENT_LENGTH_UNKNOWN);
    _server.send(200, F("text/html"), "");

    _server.sendContent_P(PSTR(
        "<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>OTA Update - "));
    _server.sendContent(_deviceId);
    _server.sendContent_P(PSTR(
        "</title><style>"
        "body{font-family:sans-serif;margin:0;padding:20px;background:#f5f5f5}"
        ".card{background:#fff;border-radius:12px;padding:20px;margin:10px 0;box-shadow:0 2px 8px rgba(0,0,0,.1)}"
        "h1{color:#e65100;font-size:20px}"
        "input[type=file]{margin:12px 0;font-size:14px}"
        ".btn{display:inline-block;padding:12px 24px;background:#e65100;color:#fff;"
        "border:none;border-radius:8px;font-size:14px;cursor:pointer}"
        ".btn:hover{background:#bf360c}"
        ".back{display:inline-block;margin-top:16px;color:#1565c0;text-decoration:none}"
        ".warn{color:#c62828;font-size:13px;margin-top:8px}"
        "</style></head><body><div class='card'>"
        "<h1>Firmware Update</h1><p>Current: v" FW_VERSION " &bull; "));
    _server.sendContent(_deviceId);
    _server.sendContent_P(PSTR(
        "</p><form method='POST' action='/update' enctype='multipart/form-data'>"
        "<input type='file' name='update' accept='.bin'><br>"
        "<button type='submit' class='btn'>Upload & Update</button>"
        "</form><p class='warn'>Device will restart after update.</p>"
        "</div><a class='back' href='/'>&larr; Back to Info</a>"
        "</body></html>"));
    _server.sendContent("");
}
