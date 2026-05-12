const mqtt = require('mqtt');
const pool = require('../db/pool');

class MqttService {
  constructor() {
    this.client = null;
    this.deviceStateCallbacks = [];
  }

  connect() {
    const host = process.env.MQTT_HOST || 'localhost';
    const port = process.env.MQTT_PORT || 1883;
    const url = `mqtt://${host}:${port}`;

    this.client = mqtt.connect(url, {
      clientId: `backend_${Date.now()}`,
      username: process.env.MQTT_USER || '',
      password: process.env.MQTT_PASSWORD || '',
      reconnectPeriod: 5000,
      keepalive: 60,
    });

    this.client.on('connect', () => {
      console.log('[MQTT] Connected to broker');
      this.client.subscribe([
        'home/discovery',
        'v1/devices/+/state',
        'v1/devices/+/status',
      ], (err) => {
        if (err) console.error('[MQTT] Subscribe error:', err);
        else console.log('[MQTT] Subscribed to device topics');
      });
    });

    this.client.on('message', (topic, payload) => {
      this._handleMessage(topic, payload.toString());
    });

    this.client.on('error', (err) => {
      console.error('[MQTT] Error:', err.message);
    });

    this.client.on('reconnect', () => {
      console.log('[MQTT] Reconnecting...');
    });
  }

  async _handleMessage(topic, message) {
    try {
      // Device discovery
      if (topic === 'home/discovery') {
        await this._handleDiscovery(message);
        return;
      }

      // Device state update: v1/devices/{deviceId}/state
      const stateMatch = topic.match(/^v1\/devices\/(.+)\/state$/);
      if (stateMatch) {
        const deviceId = stateMatch[1];
        await this._handleDeviceState(deviceId, message);
        return;
      }

      // Device status (online/offline): v1/devices/{deviceId}/status
      const statusMatch = topic.match(/^v1\/devices\/(.+)\/status$/);
      if (statusMatch) {
        const deviceId = statusMatch[1];
        await this._handleDeviceStatus(deviceId, message);
        return;
      }
    } catch (err) {
      console.error('[MQTT] Handle message error:', err.message);
    }
  }

  async _handleDiscovery(message) {
    try {
      const data = JSON.parse(message);
      const deviceId = data.device_id || data.id;
      if (!deviceId) return;

      const existing = await pool.query(
        'SELECT id FROM devices WHERE device_id = $1', [deviceId]
      );

      if (existing.rows.length === 0) {
        await pool.query(
          `INSERT INTO devices (device_id, name, device_type, mqtt_topic, ip_address, firmware_version, features, is_online, last_seen)
           VALUES ($1, $2, $3, $4, $5, $6, $7, true, NOW())`,
          [
            deviceId,
            data.name || deviceId,
            data.type || 'switch',
            data.base_topic || `v1/devices/${deviceId}`,
            data.ip || null,
            data.firmware || null,
            JSON.stringify(data.features || ['relay']),
          ]
        );
        console.log(`[MQTT] New device discovered: ${deviceId}`);
      } else {
        await pool.query(
          `UPDATE devices SET ip_address = COALESCE($2, ip_address),
           firmware_version = COALESCE($3, firmware_version),
           features = COALESCE($4, features),
           is_online = true, last_seen = NOW(), updated_at = NOW()
           WHERE device_id = $1`,
          [deviceId, data.ip || null, data.firmware || null,
           data.features ? JSON.stringify(data.features) : null]
        );
      }

      await pool.query(
        `INSERT INTO device_logs (device_id, event_type, data) VALUES ($1, 'discovery', $2)`,
        [deviceId, JSON.stringify(data)]
      );
    } catch (err) {
      console.error('[MQTT] Discovery error:', err.message);
    }
  }

  async _handleDeviceState(deviceId, message) {
    try {
      const state = JSON.parse(message);

      await pool.query(
        `UPDATE devices SET last_state = $2, is_online = true, last_seen = NOW(), updated_at = NOW()
         WHERE device_id = $1`,
        [deviceId, JSON.stringify(state)]
      );

      await pool.query(
        `INSERT INTO device_logs (device_id, event_type, data) VALUES ($1, 'state_change', $2)`,
        [deviceId, JSON.stringify(state)]
      );

      // Notify automation engine
      for (const cb of this.deviceStateCallbacks) {
        cb(deviceId, state);
      }
    } catch (err) {
      console.error('[MQTT] State update error:', err.message);
    }
  }

  async _handleDeviceStatus(deviceId, message) {
    try {
      const isOnline = message === 'online' || message === '1';
      await pool.query(
        `UPDATE devices SET is_online = $2, last_seen = NOW(), updated_at = NOW() WHERE device_id = $1`,
        [deviceId, isOnline]
      );

      await pool.query(
        `INSERT INTO device_logs (device_id, event_type, data) VALUES ($1, $2, '{}'::jsonb)`,
        [deviceId, isOnline ? 'online' : 'offline']
      );
    } catch (err) {
      console.error('[MQTT] Status update error:', err.message);
    }
  }

  onDeviceState(callback) {
    this.deviceStateCallbacks.push(callback);
  }

  publishCommand(deviceId, feature, state) {
    if (!this.client || !this.client.connected) {
      console.error('[MQTT] Not connected, cannot publish');
      return false;
    }

    const topic = `v1/devices/${deviceId}/command`;
    const payload = JSON.stringify({ [feature]: state });
    this.client.publish(topic, payload, { qos: 1 });
    console.log(`[MQTT] Command → ${topic}: ${payload}`);
    return true;
  }

  publishRaw(topic, payload, options = {}) {
    if (!this.client || !this.client.connected) return false;
    this.client.publish(topic, typeof payload === 'string' ? payload : JSON.stringify(payload), options);
    return true;
  }
}

module.exports = new MqttService();
