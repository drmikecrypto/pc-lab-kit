<?php

declare(strict_types=1);

namespace App\Services;

use App\Support\Env;

/**
 * Checks GitHub releases for newer PCVerse versions.
 */
class AppUpdateService
{
    /** @return array<string, mixed> */
    public function check(bool $forceRefresh = false): array
    {
        $cfg = require dirname(__DIR__, 2) . '/config/app.php';
        $current = (string) ($cfg['version'] ?? '1.0.0');
        $owner = (string) ($cfg['github']['owner'] ?? 'drmikecrypto');
        $repo = (string) ($cfg['github']['repo'] ?? 'pc-lab-kit');

        $cached = $forceRefresh ? null : $this->readCache();
        if ($cached !== null) {
            $cached['current_version'] = $current;

            return $this->finalize($cached, $current);
        }

        $release = $this->fetchLatestRelease($owner, $repo);
        if ($release === null) {
            return [
                'ok' => false,
                'current_version' => $current,
                'latest_version' => $current,
                'update_available' => false,
                'github_owner' => $owner,
                'github_repo' => $repo,
                'message' => 'Could not reach GitHub releases. Try again later.',
            ];
        }

        $payload = [
            'ok' => true,
            'fetched_at' => date('c'),
            'latest_version' => $release['version'],
            'release_name' => $release['name'],
            'release_url' => $release['url'],
            'download_windows' => $release['download_windows'],
            'download_linux' => $release['download_linux'],
            'published_at' => $release['published_at'],
            'release_notes' => $release['notes'],
            'github_owner' => $owner,
            'github_repo' => $repo,
        ];
        $this->writeCache($payload);

        return $this->finalize($payload, $current);
    }

    /** @param array<string, mixed> $payload */
    private function finalize(array $payload, string $current): array
    {
        $latest = (string) ($payload['latest_version'] ?? $current);
        $payload['current_version'] = $current;
        $payload['update_available'] = $this->isNewer($latest, $current);

        return $payload;
    }

    /** @return array<string, mixed>|null */
    private function fetchLatestRelease(string $owner, string $repo): ?array
    {
        $url = "https://api.github.com/repos/{$owner}/{$repo}/releases/latest";
        $ctx = stream_context_create([
            'http' => [
                'method' => 'GET',
                'timeout' => 8,
                'header' => implode("\r\n", [
                    'User-Agent: PCVerse-UpdateChecker',
                    'Accept: application/vnd.github+json',
                ]),
            ],
        ]);

        $raw = @file_get_contents($url, false, $ctx);
        if ($raw === false || $raw === '') {
            return null;
        }

        $json = json_decode($raw, true);
        if (!is_array($json)) {
            return null;
        }

        $tag = ltrim((string) ($json['tag_name'] ?? ''), 'vV');
        if ($tag === '') {
            return null;
        }

        $assets = is_array($json['assets'] ?? null) ? $json['assets'] : [];
        $winUrl = '';
        $linuxUrl = '';
        foreach ($assets as $asset) {
            if (!is_array($asset)) {
                continue;
            }
            $name = strtolower((string) ($asset['name'] ?? ''));
            $browser = (string) ($asset['browser_download_url'] ?? '');
            if ($name === 'pcverse-setup-windows-x64.exe' || str_contains($name, 'windows')) {
                $winUrl = $browser;
            }
            if ($name === 'pcverse-setup-linux-x64.run' || str_contains($name, 'linux')) {
                $linuxUrl = $browser;
            }
        }

        return [
            'version' => $tag,
            'name' => (string) ($json['name'] ?? ('PCVerse ' . $tag)),
            'url' => (string) ($json['html_url'] ?? "https://github.com/{$owner}/{$repo}/releases/latest"),
            'published_at' => (string) ($json['published_at'] ?? ''),
            'notes' => $this->trimNotes((string) ($json['body'] ?? '')),
            'download_windows' => $winUrl,
            'download_linux' => $linuxUrl,
        ];
    }

    private function trimNotes(string $body): string
    {
        $body = trim($body);
        if ($body === '') {
            return '';
        }
        if (strlen($body) > 600) {
            return substr($body, 0, 597) . '...';
        }

        return $body;
    }

    private function isNewer(string $latest, string $current): bool
    {
        if ($latest === $current) {
            return false;
        }

        return version_compare($latest, $current, '>');
    }

    /** @return array<string, mixed>|null */
    private function readCache(): ?array
    {
        $path = $this->cachePath();
        if (!is_file($path)) {
            return null;
        }
        $json = json_decode((string) file_get_contents($path), true);
        if (!is_array($json)) {
            return null;
        }
        $fetched = strtotime((string) ($json['fetched_at'] ?? ''));
        $ttl = (int) Env::get('UPDATE_CHECK_TTL_SECONDS', '21600');
        if ($fetched === false || (time() - $fetched) > max(300, $ttl)) {
            return null;
        }

        return $json;
    }

    /** @param array<string, mixed> $payload */
    private function writeCache(array $payload): void
    {
        $dir = dirname($this->cachePath());
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        file_put_contents($this->cachePath(), json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    }

    private function cachePath(): string
    {
        return dirname(__DIR__, 2) . '/storage/cache/github-release.json';
    }
}
