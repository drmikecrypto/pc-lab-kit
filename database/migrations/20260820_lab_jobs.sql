-- Lab job queue for burn-in, batch suite, enterprise mode
CREATE TABLE IF NOT EXISTS lab_jobs (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    fingerprint TEXT,
    payload_json TEXT NOT NULL DEFAULT '{}',
    result_json TEXT NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'queued',
    progress INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_lab_jobs_status ON lab_jobs(status, created_at);
