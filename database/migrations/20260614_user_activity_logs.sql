CREATE TABLE IF NOT EXISTS user_activity_logs (
    id INTEGER PRIMARY KEY,
    fingerprint VARCHAR(64) NOT NULL,
    user_id INTEGER,
    event_type VARCHAR(100) NOT NULL,
    target_type VARCHAR(64),
    target_id VARCHAR(64),
    url TEXT,
    referrer TEXT,
    dwell_time_seconds INTEGER DEFAULT 0,
    metadata TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_activity_logs_event ON user_activity_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_user_activity_logs_fp ON user_activity_logs(fingerprint);
