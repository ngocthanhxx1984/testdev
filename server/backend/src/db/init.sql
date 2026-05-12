-- IoT Ecosystem Database Schema

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    display_name VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Devices table
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id VARCHAR(100) UNIQUE NOT NULL,  -- e.g. ESP_AABBCC
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(100) NOT NULL DEFAULT 'New Device',
    device_type VARCHAR(50) NOT NULL DEFAULT 'switch',  -- switch, light, sensor, etc.
    mqtt_topic VARCHAR(200) NOT NULL,
    ip_address VARCHAR(45),
    firmware_version VARCHAR(20),
    features JSONB DEFAULT '[]'::jsonb,
    is_online BOOLEAN DEFAULT false,
    last_state JSONB DEFAULT '{}'::jsonb,
    last_seen TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Automation rules table
CREATE TABLE IF NOT EXISTS automations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    automation_type VARCHAR(20) NOT NULL DEFAULT 'schedule',  -- schedule, countdown, trigger
    enabled BOOLEAN DEFAULT true,
    config JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- Schedule: { "time": "07:00", "days": [1,2,3,4,5], "device_id": "...", "feature": "relay", "state": true }
    -- Countdown: { "duration_seconds": 300, "device_id": "...", "feature": "relay", "state": false }
    -- Trigger: { "source_device": "...", "source_feature": "...", "condition": "==", "value": true, "target_device": "...", "target_feature": "...", "target_state": true }
    last_executed TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Automation execution log
CREATE TABLE IF NOT EXISTS automation_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    automation_id UUID REFERENCES automations(id) ON DELETE SET NULL,
    automation_name VARCHAR(100),
    status VARCHAR(20) NOT NULL DEFAULT 'success',  -- success, failed, skipped
    details TEXT,
    executed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Device activity log
CREATE TABLE IF NOT EXISTS device_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id VARCHAR(100),
    event_type VARCHAR(50) NOT NULL,  -- state_change, online, offline, command, discovery
    data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Active countdown timers (volatile, recreated on restart)
CREATE TABLE IF NOT EXISTS active_countdowns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    automation_id UUID REFERENCES automations(id) ON DELETE CASCADE,
    remaining_seconds INTEGER NOT NULL,
    target_device VARCHAR(100) NOT NULL,
    target_feature VARCHAR(50) NOT NULL,
    target_state BOOLEAN NOT NULL,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_devices_device_id ON devices(device_id);
CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
CREATE INDEX IF NOT EXISTS idx_automations_user_id ON automations(user_id);
CREATE INDEX IF NOT EXISTS idx_automations_enabled ON automations(enabled);
CREATE INDEX IF NOT EXISTS idx_device_logs_device_id ON device_logs(device_id);
CREATE INDEX IF NOT EXISTS idx_device_logs_created ON device_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_automation_logs_created ON automation_logs(executed_at);

-- Cleanup old logs function (keep last 30 days)
CREATE OR REPLACE FUNCTION cleanup_old_logs() RETURNS void AS $$
BEGIN
    DELETE FROM device_logs WHERE created_at < NOW() - INTERVAL '30 days';
    DELETE FROM automation_logs WHERE executed_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;
