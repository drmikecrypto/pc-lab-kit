<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Local user settings persisted on disk (BYOK API key, etc.).
 * Environment variables override file values when set.
 */
class SettingsService
{
    private string $path;

    public function __construct(?string $projectRoot = null)
    {
        $root = $projectRoot ?? dirname(__DIR__, 2);
        $this->path = $root . '/storage/settings/local.json';
    }

    /** @return array{api_key: string, base_url: string, model: string, source: string} */
    public function llmConfig(): array
    {
        $app = require dirname(__DIR__, 2) . '/config/app.php';
        $file = $this->readFile();
        $envKey = trim((string) ($app['llm']['api_key'] ?? ''));
        $fileKeyRaw = trim((string) ($file['llm_api_key'] ?? ''));
        $fileKey = $fileKeyRaw !== '' ? $this->unwrapSecret($fileKeyRaw) : '';
        if ($fileKey === '' && $fileKeyRaw !== '' && !str_starts_with($fileKeyRaw, 'v1:') && !str_starts_with($fileKeyRaw, 'plain:')) {
            $fileKey = $fileKeyRaw;
        }

        $apiKey = $envKey !== '' ? $envKey : $fileKey;
        $source = $envKey !== '' ? 'env' : ($fileKey !== '' ? 'local' : 'none');

        $baseUrl = trim((string) ($file['llm_base_url'] ?? ''));
        if ($baseUrl === '') {
            $baseUrl = (string) ($app['llm']['base_url'] ?? 'https://api.openai.com/v1');
        }

        $model = trim((string) ($file['llm_model'] ?? ''));
        if ($model === '') {
            $model = (string) ($app['llm']['model'] ?? 'gpt-4o-mini');
        }

        return [
            'api_key' => $apiKey,
            'base_url' => rtrim($baseUrl, '/'),
            'model' => $model,
            'source' => $source,
        ];
    }

    /** @return array<string, mixed> */
    public function publicSettings(): array
    {
        $cfg = $this->llmConfig();

        return [
            'ai_configured' => $cfg['api_key'] !== '',
            'llm_base_url' => $cfg['base_url'],
            'llm_model' => $cfg['model'],
            'api_key_hint' => self::maskKey($cfg['api_key']),
            'source' => $cfg['source'],
            'shop_name' => $this->shopName(),
            'shop_key_configured' => $this->shopKeyConfigured(),
            'federated_benchmarks_opt_in' => !empty($this->readFile()['federated_benchmarks_opt_in']),
        ];
    }

    public function shopName(): string
    {
        $name = trim((string) ($this->readFile()['shop_name'] ?? ''));

        return $name !== '' ? substr($name, 0, 80) : 'PC Lab Kit';
    }

    /**
     * HMAC shop signing key for .pclab / cert integrity.
     * Persisted locally; on Windows optionally wrapped via machine-scoped key file.
     */
    public function shopSigningKey(): string
    {
        $file = $this->readFile();
        $key = trim((string) ($file['shop_signing_key'] ?? ''));
        if ($key !== '') {
            return $this->unwrapSecret($key);
        }
        $key = bin2hex(random_bytes(32));
        $file['shop_signing_key'] = $this->wrapSecret($key);
        $this->writeFile($file);

        return $key;
    }

    public function shopKeyConfigured(): bool
    {
        return trim((string) ($this->readFile()['shop_signing_key'] ?? '')) !== '';
    }

    /** Protect secrets at rest with AES-256-GCM + machine-local key material. */
    private function wrapSecret(string $plain): string
    {
        $material = $this->machineKeyMaterial();
        $iv = random_bytes(12);
        $tag = '';
        $cipher = openssl_encrypt($plain, 'aes-256-gcm', $material, OPENSSL_RAW_DATA, $iv, $tag);
        if ($cipher === false) {
            return 'plain:' . $plain;
        }

        return 'v1:' . base64_encode($iv . $tag . $cipher);
    }

    private function unwrapSecret(string $stored): string
    {
        if (str_starts_with($stored, 'plain:')) {
            return substr($stored, 6);
        }
        if (!str_starts_with($stored, 'v1:')) {
            return $stored;
        }
        $raw = base64_decode(substr($stored, 3), true);
        if ($raw === false || strlen($raw) < 28) {
            return '';
        }
        $iv = substr($raw, 0, 12);
        $tag = substr($raw, 12, 16);
        $cipher = substr($raw, 28);
        $plain = openssl_decrypt($cipher, 'aes-256-gcm', $this->machineKeyMaterial(), OPENSSL_RAW_DATA, $iv, $tag);

        return is_string($plain) ? $plain : '';
    }

    private function machineKeyMaterial(): string
    {
        $seed = php_uname('n') . '|' . (getenv('COMPUTERNAME') ?: '') . '|pclab-shop-v1';
        $path = dirname($this->path) . '/machine.key';
        if (!is_file($path)) {
            $dir = dirname($path);
            if (!is_dir($dir)) {
                mkdir($dir, 0755, true);
            }
            file_put_contents($path, bin2hex(random_bytes(32)));
        }
        $fileKey = trim((string) file_get_contents($path));

        return hash('sha256', $seed . '|' . $fileKey, true);
    }

    /** @param array<string, mixed> $input */
    public function save(array $input): array
    {
        $file = $this->readFile();

        if (!empty($input['clear_api_key'])) {
            unset($file['llm_api_key']);
        } else {
            $key = trim((string) ($input['llm_api_key'] ?? ''));
            if ($key !== '') {
                $file['llm_api_key'] = $this->wrapSecret($key);
            }
        }

        if (!empty($input['rotate_shop_key'])) {
            $file['shop_signing_key'] = $this->wrapSecret(bin2hex(random_bytes(32)));
        }

        $base = trim((string) ($input['llm_base_url'] ?? ''));
        if ($base !== '') {
            if (!filter_var($base, FILTER_VALIDATE_URL)) {
                throw new \InvalidArgumentException('Invalid API base URL.');
            }
            $file['llm_base_url'] = rtrim($base, '/');
        }

        $model = trim((string) ($input['llm_model'] ?? ''));
        if ($model !== '') {
            $file['llm_model'] = substr($model, 0, 80);
        }

        if (array_key_exists('shop_name', $input)) {
            $shop = trim((string) $input['shop_name']);
            if ($shop === '') {
                unset($file['shop_name']);
            } else {
                $file['shop_name'] = substr($shop, 0, 80);
            }
        }

        if (array_key_exists('federated_benchmarks_opt_in', $input)) {
            $file['federated_benchmarks_opt_in'] = !empty($input['federated_benchmarks_opt_in']);
        }

        $this->writeFile($file);

        return $this->publicSettings();
    }

    public function diagnosticGamesAutoRefresh(): bool
    {
        return false;
    }

    public function diagnosticGamesRefreshDays(): int
    {
        return 30;
    }

    public function clearCache(): void
    {
    }

    public function llmMaxOutputTokensJson(): int
    {
        return 1200;
    }

    public function llmMaxOutputTokensArticle(): int
    {
        return 2000;
    }

    public function llmDailyRequestCap(): int
    {
        return 0;
    }

    public static function maskKey(string $key): ?string
    {
        $key = trim($key);
        if ($key === '') {
            return null;
        }
        if (strlen($key) <= 8) {
            return '••••••••';
        }

        return substr($key, 0, 3) . '…' . substr($key, -4);
    }

    /** @return array<string, mixed> */
    private function readFile(): array
    {
        if (!is_file($this->path)) {
            return [];
        }
        $data = json_decode((string) file_get_contents($this->path), true);

        return is_array($data) ? $data : [];
    }

    /** @param array<string, mixed> $data */
    private function writeFile(array $data): void
    {
        $dir = dirname($this->path);
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }
        file_put_contents(
            $this->path,
            json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)
        );
    }
}
