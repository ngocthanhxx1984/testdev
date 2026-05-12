const cron = require('node-cron');
const pool = require('../db/pool');
const mqttService = require('./mqttService');

class AutomationEngine {
  constructor() {
    this.scheduledJobs = new Map();
    this.activeCountdowns = new Map();
  }

  start() {
    // Check schedules every minute
    cron.schedule('* * * * *', () => this._checkSchedules());

    // Check countdowns every second
    setInterval(() => this._tickCountdowns(), 1000);

    // Listen for device state changes (trigger automations)
    mqttService.onDeviceState((deviceId, state) => {
      this._checkTriggers(deviceId, state);
    });

    // Restore active countdowns from DB
    this._restoreCountdowns();

    // Cleanup old logs daily at 3 AM
    cron.schedule('0 3 * * *', () => this._cleanupLogs());

    console.log('[AUTOMATION] Engine started');
  }

  async _checkSchedules() {
    try {
      const now = new Date();
      const currentTime = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
      const currentDay = now.getDay(); // 0=Sun, 1=Mon...

      const { rows } = await pool.query(
        `SELECT * FROM automations WHERE enabled = true AND automation_type = 'schedule'`
      );

      for (const rule of rows) {
        const config = rule.config;
        if (config.time !== currentTime) continue;

        // Check day of week
        if (config.days && config.days.length > 0 && !config.days.includes(currentDay)) continue;

        // Execute
        const success = mqttService.publishCommand(config.device_id, config.feature || 'relay', config.state);

        await pool.query(
          `UPDATE automations SET last_executed = NOW() WHERE id = $1`, [rule.id]
        );

        await pool.query(
          `INSERT INTO automation_logs (automation_id, automation_name, status, details)
           VALUES ($1, $2, $3, $4)`,
          [rule.id, rule.name, success ? 'success' : 'failed',
           `Schedule: ${config.time} → ${config.device_id}.${config.feature} = ${config.state}`]
        );
      }
    } catch (err) {
      console.error('[AUTOMATION] Schedule check error:', err.message);
    }
  }

  async _checkTriggers(deviceId, state) {
    try {
      const { rows } = await pool.query(
        `SELECT * FROM automations WHERE enabled = true AND automation_type = 'trigger'`
      );

      for (const rule of rows) {
        const config = rule.config;
        if (config.source_device !== deviceId) continue;

        const sourceValue = state[config.source_feature];
        if (sourceValue === undefined) continue;

        let conditionMet = false;
        switch (config.condition) {
          case '==': conditionMet = sourceValue == config.value; break;
          case '!=': conditionMet = sourceValue != config.value; break;
          case '>':  conditionMet = sourceValue > config.value; break;
          case '<':  conditionMet = sourceValue < config.value; break;
          case '>=': conditionMet = sourceValue >= config.value; break;
          case '<=': conditionMet = sourceValue <= config.value; break;
          default: conditionMet = sourceValue == config.value;
        }

        if (conditionMet) {
          const success = mqttService.publishCommand(
            config.target_device, config.target_feature || 'relay', config.target_state
          );

          await pool.query(
            `UPDATE automations SET last_executed = NOW() WHERE id = $1`, [rule.id]
          );

          await pool.query(
            `INSERT INTO automation_logs (automation_id, automation_name, status, details)
             VALUES ($1, $2, $3, $4)`,
            [rule.id, rule.name, success ? 'success' : 'failed',
             `Trigger: ${deviceId}.${config.source_feature}=${sourceValue} → ${config.target_device}.${config.target_feature}=${config.target_state}`]
          );
        }
      }
    } catch (err) {
      console.error('[AUTOMATION] Trigger check error:', err.message);
    }
  }

  async startCountdown(automationId) {
    try {
      const { rows } = await pool.query(
        'SELECT * FROM automations WHERE id = $1', [automationId]
      );
      if (rows.length === 0) return { error: 'Automation not found' };

      const rule = rows[0];
      const config = rule.config;
      const expiresAt = new Date(Date.now() + config.duration_seconds * 1000);

      // Save to DB
      await pool.query(
        `INSERT INTO active_countdowns (automation_id, remaining_seconds, target_device, target_feature, target_state, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (automation_id) DO UPDATE SET remaining_seconds = $2, expires_at = $6, started_at = NOW()`,
        [automationId, config.duration_seconds, config.device_id,
         config.feature || 'relay', config.state, expiresAt]
      );

      // Track in memory
      this.activeCountdowns.set(automationId, {
        remaining: config.duration_seconds,
        deviceId: config.device_id,
        feature: config.feature || 'relay',
        state: config.state,
        name: rule.name,
      });

      return { remaining: config.duration_seconds };
    } catch (err) {
      console.error('[AUTOMATION] Start countdown error:', err.message);
      return { error: err.message };
    }
  }

  cancelCountdown(automationId) {
    this.activeCountdowns.delete(automationId);
    pool.query('DELETE FROM active_countdowns WHERE automation_id = $1', [automationId]);
    return { success: true };
  }

  getCountdownStatus(automationId) {
    const cd = this.activeCountdowns.get(automationId);
    if (!cd) return null;
    return { remaining: cd.remaining };
  }

  async _tickCountdowns() {
    for (const [automationId, cd] of this.activeCountdowns.entries()) {
      cd.remaining--;

      if (cd.remaining <= 0) {
        // Execute
        const success = mqttService.publishCommand(cd.deviceId, cd.feature, cd.state);
        this.activeCountdowns.delete(automationId);

        await pool.query('DELETE FROM active_countdowns WHERE automation_id = $1', [automationId]);
        await pool.query('UPDATE automations SET last_executed = NOW() WHERE id = $1', [automationId]);
        await pool.query(
          `INSERT INTO automation_logs (automation_id, automation_name, status, details)
           VALUES ($1, $2, $3, $4)`,
          [automationId, cd.name, success ? 'success' : 'failed',
           `Countdown finished → ${cd.deviceId}.${cd.feature} = ${cd.state}`]
        );
      }
    }
  }

  async _restoreCountdowns() {
    try {
      const { rows } = await pool.query(
        `SELECT ac.*, a.name FROM active_countdowns ac
         JOIN automations a ON a.id = ac.automation_id
         WHERE ac.expires_at > NOW()`
      );

      for (const row of rows) {
        const remaining = Math.floor((new Date(row.expires_at) - Date.now()) / 1000);
        if (remaining > 0) {
          this.activeCountdowns.set(row.automation_id, {
            remaining,
            deviceId: row.target_device,
            feature: row.target_feature,
            state: row.target_state,
            name: row.name,
          });
        }
      }

      if (rows.length > 0) {
        console.log(`[AUTOMATION] Restored ${this.activeCountdowns.size} active countdowns`);
      }
    } catch (err) {
      console.error('[AUTOMATION] Restore countdowns error:', err.message);
    }
  }

  async _cleanupLogs() {
    try {
      await pool.query('SELECT cleanup_old_logs()');
      console.log('[AUTOMATION] Old logs cleaned up');
    } catch (err) {
      console.error('[AUTOMATION] Cleanup error:', err.message);
    }
  }
}

module.exports = new AutomationEngine();
