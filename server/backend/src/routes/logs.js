const express = require('express');
const pool = require('../db/pool');
const auth = require('../middleware/auth');

const router = express.Router();

// GET /api/logs/devices — device activity log
router.get('/devices', auth, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 50, 200);
    const deviceId = req.query.device_id;

    let query = `SELECT * FROM device_logs`;
    const params = [];

    if (deviceId) {
      params.push(deviceId);
      query += ` WHERE device_id = $${params.length}`;
    }

    query += ` ORDER BY created_at DESC LIMIT $${params.length + 1}`;
    params.push(limit);

    const { rows } = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to get device logs' });
  }
});

// GET /api/logs/automations — automation execution log
router.get('/automations', auth, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 50, 200);
    const automationId = req.query.automation_id;

    let query = `SELECT * FROM automation_logs`;
    const params = [];

    if (automationId) {
      params.push(automationId);
      query += ` WHERE automation_id = $${params.length}`;
    }

    query += ` ORDER BY executed_at DESC LIMIT $${params.length + 1}`;
    params.push(limit);

    const { rows } = await pool.query(query, params);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to get automation logs' });
  }
});

module.exports = router;
