#ifndef MQTT_MANAGER_H
#define MQTT_MANAGER_H

#include <Arduino.h>
#include <ESP8266WiFi.h>

#include <PubSubClient.h>
#include <ArduinoJson.h>
#include "config.h"

class MqttManager {
public:
    using CommandCallback = std::function<void(const char* feature, bool state)>;
    using OtaCallback = std::function<void(const char* url)>;

    MqttManager();

    void begin(const char* host, uint16_t port,
               const char* user, const char* pass,
               const char* deviceId);
    void loop();
    bool isConnected();

    void publishDiscovery();
    void publishState(bool relayState, bool ledState);

    void onCommand(CommandCallback cb)  { _cmdCb = cb; }
    void onOta(OtaCallback cb)          { _otaCb = cb; }

private:
    void connect();
    void subscribe();
    void handleMessage(char* topic, byte* payload, unsigned int length);

    WiFiClient       _wifiClient;
    PubSubClient     _mqttClient;
    CommandCallback  _cmdCb;
    OtaCallback      _otaCb;

    const char* _host;
    uint16_t _port;
    const char* _user;
    const char* _pass;
    const char* _deviceId;

    char _topicCmd[48];
    char _topicState[48];
    char _topicOta[48];
    char _topicStatus[48];

    unsigned long _lastReconnect;
    unsigned long _lastDiscovery;
};

#endif // MQTT_MANAGER_H
