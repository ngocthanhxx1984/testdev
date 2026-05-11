# IoT Ecosystem — ESP8266 + HiveMQ Cloud + Flutter

A full-stack IoT system for remote device control over WiFi via MQTT. Control LED and Relay outputs from an Android app with real-time state feedback, auto-discovery, OTA firmware updates, and smart scenarios.

## Architecture

```
┌─────────────┐       TLS/8883        ┌──────────────────┐       TLS/8883        ┌─────────────┐
│  ESP8266     │ ◄──────────────────► │  HiveMQ Cloud    │ ◄──────────────────► │  Flutter App │
│  (Firmware)  │     MQTT + JSON      │  (MQTT Broker)   │     MQTT + JSON      │  (Android)   │
│              │                       │                  │                       │              │
│  GPIO12: LED │                       │  Topics:         │                       │  5-Tab UI:   │
│  GPIO15: Relay                       │  home/discovery  │                       │  Home        │
│  GPIO0: Button                       │  v1/devices/+/*  │                       │  Smart       │
└─────────────┘                       └──────────────────┘                       │  OTA Center  │
                                                                                 │  Notifications│
                                                                                 │  Settings    │
                                                                                 └─────────────┘
```

## MQTT Topic Structure

| Topic | Direction | Purpose |
|-------|-----------|---------|
| `home/discovery` | ESP → App | Device broadcasts identity + features |
| `v1/devices/{id}/command` | App → ESP | Control commands (JSON) |
| `v1/devices/{id}/state` | ESP → App | State feedback (retained) |
| `v1/devices/{id}/status` | ESP → Broker | Online/Offline (LWT, retained) |
| `v1/devices/{id}/ota` | App → ESP | OTA update command |

### Payload Examples

**Discovery** (published on connect, repeated every 30s):
```json
{"id": "device_01", "type": "esp8266", "features": ["relay", "led"], "v": "1.0.0"}
```

**Command** (from App):
```json
{"feature": "relay", "state": true}
```

**State** (from ESP):
```json
{"id": "device_01", "relay": true, "led": false, "uptime": 3600, "rssi": -45}
```

**OTA** (from App):
```json
{"cmd": "ota", "url": "http://server.com/firmware.bin"}
```

**LWT / Status**:
```json
{"id": "device_01", "status": "offline"}
```

---

## 1. ESP8266 Firmware

### Features
- **WiFiManager Captive Portal** — First-time setup via AP mode to configure WiFi + MQTT credentials
- **LittleFS Config Storage** — Persistent configuration survives reboots
- **MQTT over TLS** — Secure connection to HiveMQ Cloud on port 8883
- **Last Will & Testament (LWT)** — Broker publishes offline status if device disconnects unexpectedly
- **Periodic Discovery** — Broadcasts device identity every 30 seconds
- **Physical Button Control**:
  - Short press: Toggle Relay + LED
  - Long press (5s): Factory reset (clears WiFi + MQTT config, restarts in AP mode)
- **OTA Updates** — Remote firmware update via HTTP URL sent through MQTT

### Hardware Requirements
- ESP8266 (NodeMCU, Wemos D1 Mini, etc.)
- LED on GPIO12
- Relay module on GPIO15
- Button on GPIO0 (built-in FLASH button on most boards)

### Build & Flash

Requires [PlatformIO](https://platformio.org/).

```bash
cd firmware/esp8266_iot

# Build
pio run

# Upload via USB
pio run --target upload

# Monitor serial output
pio device monitor
```

### First-Time Setup
1. Power on the ESP8266 — it creates a WiFi AP named `ESP8266-IoT-Setup` (password: `12345678`)
2. Connect to the AP from your phone
3. The captive portal opens automatically — enter:
   - WiFi SSID & Password
   - HiveMQ Hostname (e.g. `xxxxxxxx.s1.eu.hivemq.cloud`)
   - Port: `8883`
   - MQTT Username & Password
   - Device ID (unique per device, e.g. `living_room_01`)
4. Submit — the device connects to WiFi and MQTT

---

## 2. Flutter App (Android)

### Features
- **5-Tab Navigation**: Home, Smart, OTA Center, Notifications, Settings
- **Auto-Discovery**: Automatically detects ESP8266 devices via MQTT discovery topic
- **Real-time Updates**: UI updates instantly when device states change
- **Smart Scenarios**: Create and execute multi-device automation sequences
- **OTA Center**: Push firmware updates to any online device
- **Notification History**: Track all device events (on/off, online/offline, OTA)
- **Material 3 Design**: Modern UI with light/dark theme support

### Screens

| Tab | Description |
|-----|-------------|
| **Home** | Grid of device cards with feature toggles (auto-generated from discovery) |
| **Smart** | Create/execute scenarios (e.g., "Turn All On"), quick-action FABs |
| **OTA Center** | Select online device → enter firmware URL → execute update |
| **Notifications** | Chronological event log with read/unread indicators |
| **Settings** | HiveMQ Cloud connection config (host, port, user, pass) |

### State Management
- **Provider** pattern with `ChangeNotifier`
- `MqttProvider` — Connection lifecycle, settings persistence
- `DeviceProvider` — Device registry, state tracking, command dispatch
- `ScenarioProvider` — Smart automation persistence (SharedPreferences)

### Build & Run

Requires [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.0+).

```bash
cd flutter_app/iot_controller

# Get dependencies
flutter pub get

# Run on connected Android device
flutter run

# Build APK
flutter build apk
```

### Configuration
1. Open the app → go to **Settings** tab
2. Enter your HiveMQ Cloud credentials:
   - Hostname, Port (8883), Username, Password
3. Tap **Connect**
4. Switch to **Home** tab — devices will appear as they broadcast discovery messages

---

## 3. HiveMQ Cloud Setup

1. Create a free account at [HiveMQ Cloud](https://www.hivemq.com/mqtt-cloud-broker/)
2. Create a new cluster
3. Note down the hostname (e.g., `xxxxxxxx.s1.eu.hivemq.cloud`)
4. Create credentials (username + password) under **Access Management**
5. Use these credentials in both the ESP8266 firmware (via captive portal) and the Flutter app (Settings tab)

---

## Project Structure

```
├── firmware/
│   └── esp8266_iot/
│       ├── platformio.ini          # PlatformIO config & dependencies
│       └── src/
│           ├── config.h            # Pin definitions, MQTT topics, constants
│           ├── config_manager.h/.cpp  # LittleFS config read/write
│           ├── mqtt_manager.h/.cpp    # MQTT client with TLS, LWT, discovery
│           └── main.cpp            # Entry point, WiFiManager, button handler, OTA
│
├── flutter_app/
│   └── iot_controller/
│       ├── pubspec.yaml            # Flutter dependencies
│       ├── lib/
│       │   ├── main.dart           # App entry, MultiProvider, navigation
│       │   ├── models/
│       │   │   ├── device.dart     # IoTDevice model
│       │   │   ├── notification_item.dart
│       │   │   └── smart_scenario.dart
│       │   ├── services/
│       │   │   └── mqtt_service.dart  # MQTT client wrapper
│       │   ├── providers/
│       │   │   ├── mqtt_provider.dart    # Connection state management
│       │   │   ├── device_provider.dart  # Device registry & commands
│       │   │   └── scenario_provider.dart # Smart scenarios
│       │   └── screens/
│       │       ├── home_screen.dart        # Device grid with feature toggles
│       │       ├── smart_screen.dart       # Scenario management
│       │       ├── ota_screen.dart         # OTA update center
│       │       ├── notification_screen.dart # Event history
│       │       └── settings_screen.dart    # MQTT broker config
│       └── android/                # Android platform files
│
└── README.md
```

## License

MIT
