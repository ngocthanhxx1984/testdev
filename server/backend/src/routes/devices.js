const express = require('express');
const pool = require('../db/pool');
const auth = require('../middleware/auth');
const mqttService = require('../services/mqttService');

const router = express.Router();

// GET /api/devices — list all devices
router.get('/', auth, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT id, device_id, name, device_type, mqtt_topic, ip_address,
              firmware_version, features, is_online, last_state, last_seen,
              user_id, created_at
       FROM devices ORDER BY created_at DESC`
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to get devices' });
  }
});

// GET /api/devices/:deviceId — device detail
router.get('/:deviceId', auth, async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT * FROM devices WHERE device_id = $1', [req.params.deviceId]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Device not found' });
    }
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to get device' });
  }
});

// PUT /api/devices/:deviceId — update device info (name, type)
router.put('/:deviceId', auth, async (req, res) => {
  try {
    const { name, device_type } = req.body;
    const { rows } = await pool.query(
      `UPDATE devices SET
        name = COALESCE($2, name),
        device_type = COALESCE($3, device_type),
        user_id = $4,
        updated_at = NOW()
       WHERE device_id = $1
       RETURNING *`,
      [req.params.deviceId, name, device_type, req.userId]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Device not found' });
    }
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to update device' });
  }
});

// POST /api/devices/:deviceId/command — send command to device
router.post('/:deviceId/command', auth, async (req, res) => {
  try {
    const { feature, state } = req.body;
    if (feature === undefined || state === undefined) {
      return res.status(400).json({ error: 'feature and state required' });
    }

    const success = mqttService.publishCommand(req.params.deviceId, feature, state);

    await pool.query(
      `INSERT INTO device_logs (device_id, event_type, data) VALUES ($1, 'command', $2)`,
      [req.params.deviceId, JSON.stringify({ feature, state, user: req.username })]
    );

    res.json({ success, device_id: req.params.deviceId, feature, state });
  } catch (err) {
    res.status(500).json({ error: 'Failed to send command' });
  }
});

// DELETE /api/devices/:deviceId — remove device
router.delete('/:deviceId', auth, async (req, res) => {
  try {
    const result = await pool.query(
      'DELETE FROM devices WHERE device_id = $1 RETURNING id', [req.params.deviceId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Device not found' });
    }
    res.json({ message: 'Device deleted' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete device' });
  }
});

module.exports = router;
