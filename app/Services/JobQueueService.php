<?php

declare(strict_types=1);

namespace App\Services;

use App\Database;

/**
 * SQLite-backed job queue for long-running lab work (burn-in, batch, suite).
 */
class JobQueueService
{
    public function enqueue(string $type, array $payload, ?string $fingerprint = null): string
    {
        $id = bin2hex(random_bytes(8));
        Database::pdo()->prepare(
            'INSERT INTO lab_jobs (id, type, fingerprint, payload_json, status, progress, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, 0, datetime("now"), datetime("now"))'
        )->execute([
            $id,
            substr($type, 0, 64),
            $fingerprint !== null ? substr($fingerprint, 0, 64) : null,
            json_encode($payload, JSON_UNESCAPED_UNICODE),
            'queued',
        ]);

        return $id;
    }

    /** @return array<string, mixed>|null */
    public function get(string $id): ?array
    {
        $st = Database::pdo()->prepare('SELECT * FROM lab_jobs WHERE id = ? LIMIT 1');
        $st->execute([$id]);
        $row = $st->fetch(\PDO::FETCH_ASSOC);

        return is_array($row) ? $this->normalizeRow($row) : null;
    }

    public function updateProgress(string $id, int $progress, string $status = 'running'): void
    {
        Database::pdo()->prepare(
            'UPDATE lab_jobs SET progress = ?, status = ?, updated_at = datetime("now") WHERE id = ?'
        )->execute([max(0, min(100, $progress)), $status, $id]);
    }

    /** @param array<string, mixed> $result */
    public function complete(string $id, array $result): void
    {
        Database::pdo()->prepare(
            'UPDATE lab_jobs SET progress = 100, status = ?, result_json = ?, leased_until = NULL, lease_owner = NULL, updated_at = datetime("now") WHERE id = ?'
        )->execute(['complete', json_encode($result, JSON_UNESCAPED_UNICODE), $id]);
    }

    public function fail(string $id, string $message, bool $requeue = false): void
    {
        if ($requeue) {
            Database::pdo()->prepare(
                'UPDATE lab_jobs SET status = ?, leased_until = NULL, lease_owner = NULL, result_json = ?, updated_at = datetime("now") WHERE id = ?'
            )->execute(['queued', json_encode(['error' => $message], JSON_UNESCAPED_UNICODE), $id]);

            return;
        }
        Database::pdo()->prepare(
            'UPDATE lab_jobs SET status = ?, leased_until = NULL, lease_owner = NULL, result_json = ?, updated_at = datetime("now") WHERE id = ?'
        )->execute(['failed', json_encode(['error' => $message], JSON_UNESCAPED_UNICODE), $id]);
    }

    /**
     * Lease one queued (or expired-lease) job for exclusive processing.
     *
     * @return array<string, mixed>|null
     */
    public function leaseNext(string $owner, int $leaseSeconds = 300, ?string $type = null): ?array
    {
        $pdo = Database::pdo();
        $pdo->beginTransaction();
        try {
            $sql = 'SELECT * FROM lab_jobs
                    WHERE status IN ("queued","running")
                      AND (leased_until IS NULL OR leased_until < datetime("now"))';
            $params = [];
            if ($type !== null && $type !== '') {
                $sql .= ' AND type = ?';
                $params[] = $type;
            }
            $sql .= ' ORDER BY created_at ASC LIMIT 1';
            $st = $pdo->prepare($sql);
            $st->execute($params);
            $row = $st->fetch(\PDO::FETCH_ASSOC);
            if (!is_array($row)) {
                $pdo->commit();

                return null;
            }
            $id = (string) $row['id'];
            $leaseUntil = gmdate('Y-m-d H:i:s', time() + max(30, $leaseSeconds));
            $upd = $pdo->prepare(
                'UPDATE lab_jobs SET status = "running", lease_owner = ?, leased_until = ?, attempts = COALESCE(attempts,0) + 1, updated_at = datetime("now") WHERE id = ?'
            );
            $upd->execute([substr($owner, 0, 64), $leaseUntil, $id]);
            $pdo->commit();

            return $this->get($id);
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
    }

    public function heartbeat(string $id, string $owner, int $leaseSeconds = 300): bool
    {
        $st = Database::pdo()->prepare(
            'UPDATE lab_jobs SET leased_until = ?, updated_at = datetime("now")
             WHERE id = ? AND lease_owner = ? AND status = "running"'
        );
        $st->execute([
            gmdate('Y-m-d H:i:s', time() + max(30, $leaseSeconds)),
            $id,
            substr($owner, 0, 64),
        ]);

        return $st->rowCount() > 0;
    }

    /** @return list<array<string, mixed>> */
    public function listQueued(int $limit = 20): array
    {
        $st = Database::pdo()->prepare(
            'SELECT * FROM lab_jobs WHERE status IN ("queued","running") ORDER BY created_at ASC LIMIT ?'
        );
        $st->bindValue(1, max(1, min(100, $limit)), \PDO::PARAM_INT);
        $st->execute();
        $rows = $st->fetchAll(\PDO::FETCH_ASSOC);

        return array_map(fn ($r) => $this->normalizeRow($r), is_array($rows) ? $rows : []);
    }

    /** @param array<string, mixed> $row @return array<string, mixed> */
    private function normalizeRow(array $row): array
    {
        $row['payload'] = json_decode((string) ($row['payload_json'] ?? '{}'), true) ?: [];
        $row['result'] = json_decode((string) ($row['result_json'] ?? '{}'), true) ?: [];

        return $row;
    }
}
