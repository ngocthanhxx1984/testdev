const express = require('express');
const pool = require('../db/pool');
const auth = require('../middleware/auth');
const automationEngine = require('../services/automationEngine');

const router = express.Router();

// GET /api/automations — list user's automations
router.get('/', auth, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT id, name, automation_type, enabled, config, last_executed, created_at, updated_at
       FROM automations WHERE user_id = $1 ORDER BY created_at DESC`,
      [req.userId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to get automations' });
  }
});

// POST /api/automations — create automation
router.post('/', auth, async (req, res) => {
  try {
    const { name, automation_type, enabled, config } = req.body;

    if (!name || !automation_type || !config) {
      return res.status(400).json({ error: 'name, automation_type, and config required' });
    }

    const validTypes = ['schedule', 'countdown', 'trigger'];
    if (!validTypes.includes(automation_type)) {
      return res.status(400).json({ error: `automation_type must be one of: ${validTypes.join(', ')}` });
    }

    const { rows } = await pool.query(
      `INSERT INTO automations (user_id, name, automation_type, enabled, config)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [req.userId, name, automation_type, enabled !== false, JSON.stringify(config)]
    );

    res.status(201).json(rows[0]);
  } catch (err) {
    console.error('Create automation error:', err);
    res.status(500).json({ error: 'Failed to create automation' });
  }
});

// PUT /api/automations/:id — update automation
router.put('/:id', auth, async (req, res) => {
  try {
    const { name, enabled, config } = req.body;

    const { rows } = await pool.query(
      `UPDATE automations SET
        name = COALESCE($2, name),
        enabled = COALESCE($3, enabled),
        config = COALESCE($4, config),
        updated_at = NOW()
       WHERE id = $1 AND user_id = $5
       RETURNING *`,
      [req.params.id, name, enabled, config ? JSON.stringify(config) : null, req.userId]
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: 'Automation not found' });
    }

    // If disabled, cancel any active countdown
    if (enabled === false) {
      automationEngine.cancelCountdown(req.params.id);
    }

    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to update automation' });
  }
});

// PATCH /api/automations/:id/toggle — toggle enabled/disabled
router.patch('/:id/toggle', auth, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `UPDATE automations SET enabled = NOT enabled, updated_at = NOW()
       WHERE id = $1 AND user_id = $2
       RETURNING *`,
      [req.params.id, req.userId]
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: 'Automation not found' });
    }

    if (!rows[0].enabled) {
      automationEngine.cancelCountdown(req.params.id);
    }

    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to toggle automation' });
  }
});

// POST /api/automations/:id/countdown/start — start countdown timer
router.post('/:id/countdown/start', auth, async (req, res) => {
  try {
    const result = await automationEngine.startCountdown(req.params.id);
    if (result.error) {
      return res.status(400).json({ error: result.error });
    }
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: 'Failed to start countdown' });
  }
});

// POST /api/automations/:id/countdown/cancel — cancel countdown
router.post('/:id/countdown/cancel', auth, async (req, res) => {
  try {
    const result = automationEngine.cancelCountdown(req.params.id);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: 'Failed to cancel countdown' });
  }
});

// GET /api/automations/:id/countdown/status — get countdown remaining
router.get('/:id/countdown/status', auth, async (req, res) => {
  const status = automationEngine.getCountdownStatus(req.params.id);
  res.json(status || { remaining: null });
});

// DELETE /api/automations/:id — delete automation
router.delete('/:id', auth, async (req, res) => {
  try {
    automationEngine.cancelCountdown(req.params.id);

    const result = await pool.query(
      'DELETE FROM automations WHERE id = $1 AND user_id = $2 RETURNING id',
      [req.params.id, req.userId]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Automation not found' });
    }

    res.json({ message: 'Automation deleted' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete automation' });
  }
});

module.exports = router;
