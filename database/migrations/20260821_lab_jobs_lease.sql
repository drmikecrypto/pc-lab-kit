-- Job queue leases for worker (burn-in / batch)
ALTER TABLE lab_jobs ADD COLUMN leased_until TEXT;
ALTER TABLE lab_jobs ADD COLUMN lease_owner TEXT;
ALTER TABLE lab_jobs ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;
