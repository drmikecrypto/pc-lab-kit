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
        $fileKey = trim((string) ($file['llm_api_key'] ?? ''));

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
        ];
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
                $file['llm_api_key'] = $key;
            }
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

        $this->writeFile($file);

        return $this->publicSettings();
    }

    public function diagnosticGamesAutoRefresh(): bool
    {
        return false;
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
