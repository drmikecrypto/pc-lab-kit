CREATE TABLE IF NOT EXISTS diagnostic_reports (
    id INTEGER PRIMARY KEY AUTO_INCREMENT,
    fingerprint VARCHAR(64) NOT NULL,
    user_id INTEGER,
    mode VARCHAR(20) NOT NULL DEFAULT 'lite',
    health_score INTEGER DEFAULT 0,
    health_grade VARCHAR(2) DEFAULT 'C',
    bottleneck_type VARCHAR(32),
    bottleneck_fa VARCHAR(255),
    cpu_model VARCHAR(255),
    gpu_model VARCHAR(255),
    ram_gb INTEGER DEFAULT 0,
    form_factor VARCHAR(20) DEFAULT 'desktop',
    metrics_json TEXT,
    summary_json TEXT,
    report_json TEXT,
    report_token VARCHAR(32) NOT NULL,
    is_public INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_diagnostic_reports_created ON diagnostic_reports(created_at);
CREATE INDEX IF NOT EXISTS idx_diagnostic_reports_fp ON diagnostic_reports(fingerprint);
CREATE INDEX IF NOT EXISTS idx_diagnostic_reports_token ON diagnostic_reports(report_token);
