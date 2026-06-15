<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Standalone stub — app releases ship separately from the lab kit.
 */
class AppReleaseService
{
    public function latestPublicRelease(string $platform): ?array
    {
        return null;
    }

    public function downloadManifest(): array
    {
        return [];
    }

    public function normalizePlatform(string $platform): ?string
    {
        $p = strtolower(trim($platform));

        return in_array($p, ['windows', 'android', 'ios', 'macos'], true) ? $p : null;
    }

    public function findRelease(int $id): ?array
    {
        return null;
    }
}
