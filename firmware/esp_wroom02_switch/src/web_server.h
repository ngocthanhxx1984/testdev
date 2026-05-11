#ifndef WEB_SERVER_H
#define WEB_SERVER_H

#include <Arduino.h>
#include <ESP8266WebServer.h>
#include <ESP8266HTTPUpdateServer.h>
#include "config.h"

class DeviceWebServer {
public:
    DeviceWebServer();
    void begin(const char* deviceId, bool* relayState, bool* ledState);
    void loop();
private:
    void handleRoot();
    void handleOtaPage();
    ESP8266WebServer _server;
    ESP8266HTTPUpdateServer _httpUpdater;
    const char* _deviceId;
    bool* _relayState;
    bool* _ledState;
};

#endif
