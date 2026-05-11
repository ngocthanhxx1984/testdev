#include "config_manager.h"

ConfigManager::ConfigManager() : _initialized(false) {}

bool ConfigManager::begin() {
    _initialized = LittleFS.begin();
    if (!_initialized) {
        Serial.println(F("[CFG] LittleFS mount failed, formatting..."));
        LittleFS.format();
        _initialized = LittleFS.begin();
    }
    return _initialized;
}

bool ConfigManager::load(DeviceConfig& cfg) {
    if (!_initialized) return false;

    File file = LittleFS.open(CONFIG_FILE, "r");
    if (!file) {
        Serial.println(F("[CFG] Config file not found"));
        cfg.valid = false;
        return false;
    }

    JsonDocument doc;
    DeserializationError err = deserializeJson(doc, file);
    file.close();

    if (err) {
        Serial.printf_P(PSTR("[CFG] JSON parse error: %s\n"), err.c_str());
        cfg.valid = false;
        return false;
    }

    strlcpy(cfg.mqttHost, doc["host"] | "", sizeof(cfg.mqttHost));
    cfg.mqttPort = doc["port"] | MQTT_PORT_DEFAULT;
    strlcpy(cfg.mqttUser, doc["user"] | "", sizeof(cfg.mqttUser));
    strlcpy(cfg.mqttPass, doc["pass"] | "", sizeof(cfg.mqttPass));
    strlcpy(cfg.deviceId, doc["device_id"] | "", sizeof(cfg.deviceId));

    cfg.valid = strlen(cfg.mqttHost) > 0 && strlen(cfg.deviceId) > 0;
    Serial.printf_P(PSTR("[CFG] Loaded config: host=%s, port=%d, id=%s, valid=%d\n"),
                  cfg.mqttHost, cfg.mqttPort, cfg.deviceId, cfg.valid);
    return cfg.valid;
}

bool ConfigManager::save(const DeviceConfig& cfg) {
    if (!_initialized) return false;

    JsonDocument doc;
    doc["host"] = cfg.mqttHost;
    doc["port"] = cfg.mqttPort;
    doc["user"] = cfg.mqttUser;
    doc["pass"] = cfg.mqttPass;
    doc["device_id"] = cfg.deviceId;

    File file = LittleFS.open(CONFIG_FILE, "w");
    if (!file) {
        Serial.println(F("[CFG] Failed to open config file for writing"));
        return false;
    }

    serializeJson(doc, file);
    file.close();
    Serial.println(F("[CFG] Config saved successfully"));
    return true;
}

bool ConfigManager::clear() {
    if (!_initialized) return false;

    if (LittleFS.remove(CONFIG_FILE)) {
        Serial.println(F("[CFG] Config cleared"));
        return true;
    }
    Serial.println(F("[CFG] Failed to clear config"));
    return false;
}
