const express = require('express');
const cors = require('cors');
const pool = require('./db/pool');
const mqttService = require('./services/mqttService');
const automationEngine = require('./services/automationEngine');
const authRoutes = require('./routes/auth');
const deviceRoutes = require('./routes/devices');
const automationRoutes = require('./routes/automations');
const logRoutes = require('./routes/logs');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

// API routes
app.use('/api/auth', authRoutes);
app.use('/api/devices', deviceRoutes);
app.use('/api/automations', automationRoutes);
app.use('/api/logs', logRoutes);

// Error handler
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

async function start() {
  // Wait for database
  let retries = 10;
  while (retries > 0) {
    try {
      await pool.query('SELECT 1');
      console.log('[DB] Connected to PostgreSQL');
      break;
    } catch (err) {
      retries--;
      console.log(`[DB] Waiting for database... (${retries} retries left)`);
      await new Promise(r => setTimeout(r, 3000));
    }
  }
  if (retries === 0) {
    console.error('[DB] Could not connect to database');
    process.exit(1);
  }

  // Connect MQTT
  mqttService.connect();

  // Start automation engine
  automationEngine.start();

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`[SERVER] IoT Backend running on port ${PORT}`);
  });
}

start().catch(err => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
