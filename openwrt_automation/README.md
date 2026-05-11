# OpenWrt MQTT Automation - Server-Side Execution

Tự động hoá chạy trực tiếp trên router OpenWrt.  
Rules được thiết lập từ Android app (Flutter), gửi qua MQTT, và thực thi trên server.  
**Không phụ thuộc điện thoại** — luôn hoạt động khi router còn bật.

## Cách hoạt động

```
┌─────────────┐    MQTT: home/automation/rules    ┌──────────────┐
│  Android App │ ──────────────────────────────── │   OpenWrt     │
│  (Flutter)   │    (retained message, JSON)       │   Router      │
│              │                                   │               │
│  Tạo rules   │                                   │  automation_  │
│  qua UI      │    MQTT: v1/devices/+/command     │  manager.sh   │
│              │ ◄──────────────────────────────── │               │
│  Nhận log    │    MQTT: home/automation/log       │  → crontab    │
│  thực thi    │ ◄──────────────────────────────── │  → conditions │
└─────────────┘                                   │  → countdown  │
                                                  └──────────────┘
```

## Yêu cầu

```bash
opkg update
opkg install mosquitto-client-nossl
```

## Cài đặt

### 1. Copy scripts lên router
```bash
scp -r scripts/ root@192.168.0.121:/root/iot-automation/
ssh root@192.168.0.121 "chmod +x /root/iot-automation/*.sh"
```

### 2. Sửa cấu hình broker (nếu cần auth)
```bash
ssh root@192.168.0.121 "vi /root/iot-automation/config.sh"
# Sửa MQTT_USER và MQTT_PASS nếu broker yêu cầu
```

### 3. Khởi động automation manager
```bash
ssh root@192.168.0.121 "nohup /root/iot-automation/automation_manager.sh > /dev/null 2>&1 &"
```

### 4. Tự động chạy khi router khởi động
Thêm vào `/etc/rc.local` (trước dòng `exit 0`):
```bash
nohup /root/iot-automation/automation_manager.sh > /dev/null 2>&1 &
```

Hoặc thêm vào crontab:
```bash
crontab -e
# Thêm dòng:
@reboot nohup /root/iot-automation/automation_manager.sh > /dev/null 2>&1 &
```

## MQTT Topics

| Topic | Hướng | Mô tả |
|-------|-------|--------|
| `home/automation/rules` | App → Server | Rules JSON (retained) |
| `home/automation/countdown` | App → Server | Yêu cầu countdown start/stop |
| `home/automation/log` | Server → App | Log thực thi automation |
| `v1/devices/{id}/command` | Server → ESP | Lệnh điều khiển thiết bị |

## Cấu trúc file

| File | Mô tả |
|------|--------|
| `config.sh` | Cấu hình broker MQTT (host, port, user, pass) |
| `automation_manager.sh` | **Script chính** — nhận rules từ app, tạo crontab + monitors |
| `mqtt_cmd.sh` | Gửi lệnh MQTT tới thiết bị |
| `condition_monitor.sh` | Giám sát sensor và tự động điều khiển |
| `countdown.sh` | Hẹn giờ đếm ngược (dùng thủ công) |
| `cancel_countdown.sh` | Hủy đếm ngược |
| `schedule.sh` | Chạy lệnh theo lịch (dùng thủ công) |
| `sunrise_sunset.sh` | Automation theo giờ mặt trời |

## Các loại automation được hỗ trợ

### 1. Schedule (Lịch trình)
- Người dùng đặt giờ + ngày trong tuần trên app
- Server tạo crontab entry tự động
- Ví dụ: "Bật relay lúc 6:00 mỗi ngày"

### 2. Sunrise / Sunset (Mặt trời mọc/lặn)
- Sunrise = 06:00, Sunset = 18:00 (mặc định)
- Server tạo crontab entry cho 6:00 hoặc 18:00

### 3. Countdown (Đếm ngược)
- App gửi yêu cầu qua topic `home/automation/countdown`
- Server chạy `sleep N` rồi thực thi lệnh
- Có thể hủy bằng cách gửi action=stop

### 4. Condition (Điều kiện)
- Server subscribe topic state của sensor
- Khi điều kiện thỏa (edge trigger) → thực thi lệnh
- Ví dụ: "Khi nhiệt độ > 30°C → bật relay"

## Gửi lệnh thủ công

```bash
# Bật relay
/root/iot-automation/mqtt_cmd.sh esp01 relay true

# Tắt LED
/root/iot-automation/mqtt_cmd.sh esp01 led false

# Countdown 30 phút rồi tắt relay
/root/iot-automation/countdown.sh 1800 esp01 relay false &
```

## Xem log

```bash
cat /tmp/iot-automation.log
tail -f /tmp/iot-automation.log
```

## Ghi chú

- Broker local: `127.0.0.1:1883` (scripts dùng local cho nhanh)
- Broker từ internet: `adangdang.ddns.net:443` (ESP8266 + App dùng)
- Router port forward: 443 → 1883
- Rules được lưu retained trên broker → khi manager restart sẽ nhận lại rules ngay
