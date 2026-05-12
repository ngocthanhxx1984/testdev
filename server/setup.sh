#!/bin/bash
# IoT Ecosystem Server Setup Script
# Generates self-signed SSL certificates and starts Docker Compose

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_DIR="$SCRIPT_DIR/nginx/certs"

echo "=== IoT Ecosystem Cloud Server Setup ==="

# Generate self-signed SSL certificates
if [ ! -f "$CERT_DIR/server.crt" ]; then
    echo "[CERT] Generating self-signed SSL certificates..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -days 3650 \
        -newkey rsa:2048 \
        -keyout "$CERT_DIR/server.key" \
        -out "$CERT_DIR/server.crt" \
        -subj "/C=VN/ST=HCM/L=HCM/O=IoTEcosystem/CN=iot.local" \
        -addext "subjectAltName=DNS:iot.local,DNS:localhost,IP:192.168.0.121,IP:127.0.0.1"
    echo "[CERT] Certificates generated in $CERT_DIR"
else
    echo "[CERT] Certificates already exist, skipping..."
fi

# Create .env if not exists
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "[ENV] Creating .env file..."
    cat > "$SCRIPT_DIR/.env" << 'EOF'
POSTGRES_PASSWORD=iot_secret_2024
MQTT_BACKEND_USER=backend_service
MQTT_BACKEND_PASSWORD=backend_secret_2024
JWT_SECRET=jwt_super_secret_key_2024
EOF
    echo "[ENV] .env created — edit passwords before production use!"
else
    echo "[ENV] .env already exists, skipping..."
fi

# Start services
echo "[DOCKER] Starting services..."
cd "$SCRIPT_DIR"
docker compose up -d --build

echo ""
echo "=== Setup Complete ==="
echo "API:  https://192.168.0.121/api/"
echo "MQTT: 192.168.0.121:1883 (plain) | 192.168.0.121:8883 (TLS)"
echo "MQTT WS: wss://192.168.0.121/mqtt"
echo ""
echo "Default credentials (change in .env):"
echo "  DB: iot_admin / iot_secret_2024"
echo "  JWT Secret: jwt_super_secret_key_2024"
