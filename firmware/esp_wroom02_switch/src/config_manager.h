#ifndef CONFIG_MANAGER_H
#define CONFIG_MANAGER_H

#include <Arduino.h>
#include <LittleFS.h>
#include <ArduinoJson.h>
#include "config.h"

struct DeviceConfig {
    char mqttHost[128];
    uint16_t mqttPort;
    char mqttUser[64];
    char mqttPass[64];
    char deviceId[32];
    bool valid;
};

class ConfigManager {
public:
    ConfigManager();

    bool begin();
    bool load(DeviceConfig& cfg);
    bool save(const DeviceConfig& cfg);
    bool clear();

private:
    bool _initialized;
};

#endif // CONFIG_MANAGER_H
