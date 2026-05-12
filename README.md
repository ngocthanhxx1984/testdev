# IoT Ecosystem — ESP8266 + Cloud Server + Flutter

A full-stack IoT system for remote device control via MQTT + REST API. Features Docker Compose orchestration with Mosquitto MQTT broker, Node.js backend (authentication, automation engine, device management), PostgreSQL database, and Nginx reverse proxy with HTTPS.

## Architecture

```
                                    ┌─────────────────────────────────────────────┐
                                    │          Cloud Server (Docker Compose)      │
                                    │                                             │
┌─────────────┐    MQTT/1883    ┌───┴───────────┐     ┌──────────────┐           │
│  ESP8266     │ ◄────────────► │  Mosquitto    │     │  PostgreSQL  │           │
│  (Firmware)  │                │  MQTT Broker  │     │  Database    │           │
│              │                └───┬───────────┘     └──────┬───────┘           │
│  Power Save  │                    │                        │                   │
│  Mode: HIGH  │                ┌───┴────────────────────────┴──────┐            │
└─────────────┘                │  Node.js Backend                   │            │
                               │  - JWT Authentication              │            │
                               │  - REST API (devices, automations) │            │
┌─────────────┐    HTTPS/443   │  - MQTT Bridge (subscribe/publish) │            │
│  Flutter App │ ◄────────────►│  - Automation Engine               │            │
│  (Android)   │    REST API   │    (schedules, triggers, countdowns)│            │
│              │               └───┬────────────────────────────────┘            │
│  Login/Auth  │                   │                                             │
│  MQTT + API  │               ┌───┴──────────┐                                 │
└─────────────┘               │  Nginx        │                                 │
                               │  Reverse Proxy│                                 │
                               │  + HTTPS/TLS  │                                 │
                               └──────────────┘                                 │
                                    └─────────────────────────────────────────────┘
```

## Quick Start (Server)

```bash
cd server

# One-command setup: generates SSL certs, creates .env, starts all services
chmod +x setup.sh
./setup.sh

# Or manually:
cp .env.example .env
# Edit .env with your passwords
docker compose up -d --build
```

**Services after startup:**
| Service | Port | Description |
|---------|------|-------------|
| Nginx | 80, 443 | HTTP→HTTPS redirect, reverse proxy |
| MQTT | 1883 | Plain MQTT for ESP devices |
| MQTT/TLS | 8883 | MQTT over TLS (via Nginx) |
| MQTT/WS | 9001 | WebSocket MQTT |
| API | 3000 | Node.js REST API (proxied via Nginx) |
| PostgreSQL | 5432 | Database |

## MQTT Topic Structure

| Topic | Direction | Purpose |
|-------|-----------|---------|
| `home/discovery` | ESP → Server | Device broadcasts identity + features |
| `v1/devices/{id}/command` | Server → ESP | Control commands (JSON) |
| `v1/devices/{id}/state` | ESP → Server | State feedback (retained) |
| `v1/devices/{id}/status` | ESP → Broker | Online/Offline (LWT, retained) |
| `v1/devices/{id}/ota` | App → ESP | OTA update command |

## REST API Endpoints

All API endpoints require JWT authentication (except register/login).

### Auth
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/register` | Register new user |
| POST | `/api/auth/login` | Login, returns JWT token |
| GET | `/api/auth/me` | Get current user info |
| PUT | `/api/auth/password` | Change password |

### Devices
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/devices` | List all devices |
| GET | `/api/devices/:id` | Device detail |
| PUT | `/api/devices/:id` | Update device name/type |
| POST | `/api/devices/:id/command` | Send command to device |
| DELETE | `/api/devices/:id` | Remove device |

### Automations
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/automations` | List user's automations |
| POST | `/api/automations` | Create automation |
| PUT | `/api/automations/:id` | Update automation |
| PATCH | `/api/automations/:id/toggle` | Toggle enabled/disabled |
| DELETE | `/api/automations/:id` | Delete automation |
| POST | `/api/automations/:id/countdown/start` | Start countdown timer |
| POST | `/api/automations/:id/countdown/cancel` | Cancel countdown |

### Logs
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/logs/devices` | Device activity log |
| GET | `/api/logs/automations` | Automation execution log |

---

## 1. ESP8266 Firmware

### Features
- **WiFiManager Captive Portal** — First-time setup via AP mode
- **LittleFS Config Storage** — Persistent configuration
- **MQTT Connection** — Connects to Mosquitto broker on port 1883
- **Last Will & Testament (LWT)** — Offline status on unexpected disconnect
- **Periodic Discovery** — Broadcasts identity every 60 seconds
- **Physical Button Control**: Short press toggle, Long press (5s) factory reset
- **OTA Updates** — Remote firmware update via HTTP URL
- **Power Save Mode** — WiFi light sleep, 80MHz CPU, 10dBm TX (accepts 1-2s delay)

### Build & Flash
```bash
cd firmware/esp8266_iot
pio run
pio run --target upload
```

---

## 1b. ESP-WROOM-02 Smart Switch Firmware

| Function | GPIO |
|----------|------|
| LED | GPIO12 |
| Relay | GPIO15 |
| Switch/Reset | GPIO13 |

```bash
cd firmware/esp_wroom02_switch
pio run
pio run --target upload
```

---

## 2. Flutter App (Android)

### Features
- **User Authentication** — Login/Register with JWT tokens
- **6-Tab Navigation**: Home, Entities, Automation, OTA, Notifications, Settings
- **Auto-Discovery** via MQTT + REST API device listing
- **Real-time Updates** via MQTT subscriptions
- **Automation Management** — Schedule, Countdown, Trigger (via API + MQTT)
- **Server Config** — Set backend URL and MQTT broker independently
- **Material 3 Design** with light/dark theme

### Build
```bash
cd flutter_app/iot_controller
flutter pub get
flutter build apk
```

### App Configuration
1. Launch app → **Login/Register** screen
2. Set **Server URL** (e.g., `https://192.168.0.121`)
3. Create account or login
4. Go to **Settings** → configure MQTT broker (host: `192.168.0.121`, port: `1883`)
5. Tap **Connect** — devices appear as they broadcast discovery

---

## 3. Server Setup (Docker Compose)

### Prerequisites
- Docker Engine 20+
- Docker Compose v2

### Services
- **PostgreSQL 16** — User accounts, devices, automations, logs
- **Mosquitto 2** — MQTT broker with optional authentication
- **Node.js 20** — REST API + MQTT bridge + Automation engine
- **Nginx** — Reverse proxy, HTTPS (self-signed cert), MQTT/TLS on port 8883

### Database Schema
- `users` — Authentication (bcrypt hashed passwords)
- `devices` — Device registry with last state and features
- `automations` — Schedule/Countdown/Trigger rules (JSONB config)
- `automation_logs` — Execution history
- `device_logs` — State change history (auto-cleanup after 30 days)
- `active_countdowns` — In-progress countdown timers

### Automation Engine
The Node.js backend includes a built-in automation engine:
- **Schedule** — Execute at specific time + days of week
- **Countdown** — Timer-based delayed execution (persists across restarts)
- **Trigger** — React to device state changes (condition-based)

---

## Project Structure

```
├── server/
│   ├── docker-compose.yml          # Service orchestration
│   ├── setup.sh                    # One-command setup script
│   ├── .env.example                # Environment variables template
│   ├── backend/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── src/
│   │       ├── index.js            # Express server entry point
│   │       ├── db/
│   │       │   ├── pool.js         # PostgreSQL connection pool
│   │       │   └── init.sql        # Database schema
│   │       ├── middleware/
│   │       │   └── auth.js         # JWT authentication
│   │       ├── routes/
│   │       │   ├── auth.js         # Register, Login, Profile
│   │       │   ├── devices.js      # Device CRUD + commands
│   │       │   ├── automations.js  # Automation CRUD + countdown
│   │       │   └── logs.js         # Device & automation logs
│   │       └── services/
│   │           ├── mqttService.js     # MQTT broker bridge
│   │           └── automationEngine.js # Schedule/trigger/countdown
│   ├── mosquitto/
│   │   └── config/
│   │       ├── mosquitto.conf      # Broker configuration
│   │       └── acl.conf            # Access control list
│   └── nginx/
│       └── conf/
│           └── nginx.conf          # Reverse proxy + TLS config
│
├── firmware/
│   ├── esp8266_iot/                # Main ESP8266 firmware
│   └── esp_wroom02_switch/         # ESP-WROOM-02 variant
│
├── flutter_app/
│   └── iot_controller/
│       ├── pubspec.yaml
│       └── lib/
│           ├── main.dart           # App entry + auth gate
│           ├── models/
│           ├── services/
│           │   ├── mqtt_service.dart  # MQTT client
│           │   └── api_service.dart   # REST API client (new)
│           ├── providers/
│           │   ├── auth_provider.dart    # Authentication (new)
│           │   ├── mqtt_provider.dart
│           │   ├── device_provider.dart
│           │   └── automation_provider.dart
│           └── screens/
│               ├── login_screen.dart      # Login/Register (new)
│               ├── home_screen.dart
│               ├── automation_screen.dart
│               ├── settings_screen.dart
│               └── ...
│
└── README.md
```

## License

MIT
