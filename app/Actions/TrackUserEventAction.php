<?php

declare(strict_types=1);

namespace App\Actions;

use App\Database;
use App\Support\Log;

/**
 * Local activity log for lab pulse — no monolith intelligence stack.
 */
class TrackUserEventAction
{
    public function __invoke(array $data): bool
    {
        try {
            $db = Database::connection();
            $fingerprint = self::normalizeFingerprint((string) ($data['fingerprint'] ?? 'unknown'));
            if (empty($_SESSION['fingerprint'])) {
                $_SESSION['fingerprint'] = $fingerprint;
            }

            $eventType = substr((string) ($data['event_type'] ?? 'unknown'), 0, 100);
            $meta = is_array($data['metadata'] ?? null) ? $data['metadata'] : [];
            $meta = $this->sanitizeMetadata($meta);

            $stmt = $db->prepare(
                'INSERT INTO user_activity_logs (fingerprint, user_id, event_type, target_type, target_id, url, referrer, dwell_time_seconds, metadata)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
            );
            $stmt->execute([
                $fingerprint,
                $_SESSION['user_id'] ?? null,
                $eventType,
                $data['target_type'] ?? null,
                $data['target_id'] ?? null,
                substr((string) ($data['url'] ?? ''), 0, 1000),
                substr((string) ($data['referrer'] ?? ''), 0, 1000),
                (int) ($data['dwell_time'] ?? 0),
                json_encode($meta, JSON_UNESCAPED_UNICODE) ?: '{}',
            ]);

            return true;
        } catch (\Throwable $e) {
            Log::error('Failed to track event', ['error' => $e->getMessage()]);

            return false;
        }
    }

    public static function normalizeFingerprint(string $fp): string
    {
        $fp = trim($fp);
        if ($fp === '' || $fp === 'unknown') {
            $fp = bin2hex(random_bytes(16));
        }
        if (strlen($fp) > 64) {
            $fp = hash('sha256', $fp);
        }
        if (!preg_match('/^[a-zA-Z0-9\-]{6,64}$/', $fp)) {
            $fp = hash('sha256', $fp);
        }

        return $fp;
    }

    /** @return array<string, mixed> */
    private function sanitizeMetadata(array $meta): array
    {
        $out = [];
        $i = 0;
        foreach ($meta as $k => $v) {
            if (++$i > 60) {
                break;
            }
            $key = is_string($k) ? substr($k, 0, 60) : (string) $k;
            if (is_string($v)) {
                $out[$key] = strlen($v) > 500 ? substr($v, 0, 500) : $v;
            } elseif (is_int($v) || is_float($v) || is_bool($v) || $v === null) {
                $out[$key] = $v;
            } elseif (is_array($v)) {
                $out[$key] = array_slice($v, 0, 10);
            } else {
                $out[$key] = (string) $v;
            }
        }

        return $out;
    }
}
