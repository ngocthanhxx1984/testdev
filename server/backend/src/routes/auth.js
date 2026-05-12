const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('../db/pool');
const auth = require('../middleware/auth');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'jwt_super_secret_key_2024';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '30d';

function generateToken(user) {
  return jwt.sign(
    { userId: user.id, username: user.username },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRES_IN }
  );
}

// POST /api/auth/register
router.post('/register', async (req, res) => {
  try {
    const { username, password, email, displayName } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }
    if (username.length < 3 || password.length < 6) {
      return res.status(400).json({ error: 'Username min 3 chars, password min 6 chars' });
    }

    const existing = await pool.query('SELECT id FROM users WHERE username = $1', [username]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Username already exists' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const { rows } = await pool.query(
      `INSERT INTO users (username, password_hash, email, display_name)
       VALUES ($1, $2, $3, $4) RETURNING id, username, email, display_name, created_at`,
      [username, passwordHash, email || null, displayName || username]
    );

    const user = rows[0];
    const token = generateToken(user);

    res.status(201).json({
      user: { id: user.id, username: user.username, email: user.email, displayName: user.display_name },
      token,
    });
  } catch (err) {
    console.error('Register error:', err);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    const { rows } = await pool.query('SELECT * FROM users WHERE username = $1', [username]);
    if (rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = rows[0];
    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = generateToken(user);

    res.json({
      user: { id: user.id, username: user.username, email: user.email, displayName: user.display_name },
      token,
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Login failed' });
  }
});

// GET /api/auth/me
router.get('/me', auth, async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, username, email, display_name, created_at FROM users WHERE id = $1',
      [req.userId]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    const u = rows[0];
    res.json({ id: u.id, username: u.username, email: u.email, displayName: u.display_name });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get user' });
  }
});

// PUT /api/auth/password
router.put('/password', auth, async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword || newPassword.length < 6) {
      return res.status(400).json({ error: 'Current and new password (min 6 chars) required' });
    }

    const { rows } = await pool.query('SELECT password_hash FROM users WHERE id = $1', [req.userId]);
    const valid = await bcrypt.compare(currentPassword, rows[0].password_hash);
    if (!valid) {
      return res.status(401).json({ error: 'Current password is incorrect' });
    }

    const newHash = await bcrypt.hash(newPassword, 10);
    await pool.query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2', [newHash, req.userId]);

    res.json({ message: 'Password updated' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to update password' });
  }
});

module.exports = router;
