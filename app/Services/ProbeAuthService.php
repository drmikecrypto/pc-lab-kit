<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Reads the local probe auth token (never from /health).
 * Bootstrap for same-origin PHP session clients.
 */
class ProbeAuthService
{
    /**
     * @return array{token: ?string, source: string, auth_required: bool}
     */
    public function resolve(?string $tokenFileOverride = null): array
    {
        $env = trim((string) (getenv('PCLAB_PROBE_TOKEN') ?: ''));
        if ($env !== '') {
            return ['token' => $env, 'source' => 'env', 'auth_required' => true];
        }

        $path = $tokenFileOverride ?? $this->defaultTokenPath();
        if ($path !== '' && is_file($path) && is_readable($path)) {
            $raw = trim((string) file_get_contents($path));
            if ($raw !== '') {
                return ['token' => $raw, 'source' => 'file', 'auth_required' => true];
            }
        }

        return ['token' => null, 'source' => 'none', 'auth_required' => false];
    }

    public function defaultTokenPath(): string
    {
        if (PHP_OS_FAMILY === 'Windows') {
            $local = (string) (getenv('LOCALAPPDATA') ?: '');
            if ($local !== '') {
                return $local . DIRECTORY_SEPARATOR . 'PcLabKit' . DIRECTORY_SEPARATOR . 'Probe' . DIRECTORY_SEPARATOR . 'auth.token';
            }
        }

        $xdg = (string) (getenv('XDG_DATA_HOME') ?: '');
        if ($xdg === '') {
            $home = (string) (getenv('HOME') ?: '');
            $xdg = $home !== '' ? $home . '/.local/share' : '';
        }
        if ($xdg === '') {
            return '';
        }

        return $xdg . '/PcLabKit/Probe/auth.token';
    }

    /** Allow only loopback probe bases for session bootstrap. */
    public function isLoopbackProbeBase(string $base): bool
    {
        $base = trim($base);
        if ($base === '') {
            return true;
        }
        $parts = parse_url($base);
        if (!is_array($parts)) {
            return false;
        }
        $host = strtolower((string) ($parts['host'] ?? ''));

        return $host === '127.0.0.1' || $host === 'localhost' || $host === '::1';
    }
}
