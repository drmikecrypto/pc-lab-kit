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
            'UPDATE lab_jobs SET progress = 100, status = ?, result_json = ?, updated_at = datetime("now") WHERE id = ?'
        )->execute(['complete', json_encode($result, JSON_UNESCAPED_UNICODE), $id]);
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
