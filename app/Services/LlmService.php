<?php

declare(strict_types=1);

namespace App\Services;

/**
 * BYOK OpenAI-compatible LLM client — optional; rule-based fallbacks exist in DiagnosticAiService.
 */
class LlmService
{
    private string $lastError = '';

    public function __construct(
        private ?SettingsService $settings = null,
    ) {
        $this->settings = $settings ?? new SettingsService();
    }

    public function isConfigured(): bool
    {
        return $this->config()['api_key'] !== '';
    }

    public function lastError(): string
    {
        return $this->lastError;
    }

    /** @return array{api_key: string, base_url: string, model: string} */
    private function config(): array
    {
        return $this->settings->llmConfig();
    }

    /** @return array<string, mixed>|null */
    public function generateJson(string $systemPrompt, string $userPrompt, ?int $maxTokens = null, float $temperature = 0.5): ?array
    {
        $this->lastError = '';

        if (!$this->isConfigured()) {
            $this->lastError = 'No API key configured';

            return null;
        }

        $cfg = $this->config();
        $payload = [
            'model' => $cfg['model'],
            'messages' => [
                ['role' => 'system', 'content' => $systemPrompt],
                ['role' => 'user', 'content' => $userPrompt],
            ],
            'temperature' => $temperature,
            'max_tokens' => $maxTokens ?? 1200,
            'response_format' => ['type' => 'json_object'],
        ];

        $body = $this->post('/chat/completions', $payload);
        if ($body === null) {
            return null;
        }

        $text = (string) ($body['choices'][0]['message']['content'] ?? '');
        $text = preg_replace('/^```json\s*|```$/m', '', trim($text)) ?? $text;
        $decoded = json_decode($text, true);

        if (!is_array($decoded)) {
            $this->lastError = 'Model returned invalid JSON';

            return null;
        }

        return $decoded;
    }

    /** @param array<string, mixed> $payload @return array<string, mixed>|null */
    private function post(string $path, array $payload): ?array
    {
        $cfg = $this->config();
        $appCfg = (require dirname(__DIR__, 2) . '/config/app.php')['llm'];
        $url = rtrim($cfg['base_url'], '/') . $path;
        $ch = curl_init($url);
        if ($ch === false) {
            $this->lastError = 'Could not initialize HTTP client';

            return null;
        }

        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $cfg['api_key'],
                'Content-Type: application/json',
            ],
            CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE),
            CURLOPT_TIMEOUT => (int) ($appCfg['timeout_seconds'] ?? 120),
        ]);

        $raw = curl_exec($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlErr = curl_error($ch);
        curl_close($ch);

        if ($raw === false) {
            $this->lastError = $curlErr !== '' ? $curlErr : 'Network request failed';

            return null;
        }

        if ($code >= 400) {
            $decoded = json_decode($raw, true);
            $msg = is_array($decoded) ? (string) ($decoded['error']['message'] ?? $decoded['error'] ?? '') : '';
            $this->lastError = $msg !== '' ? "HTTP {$code}: {$msg}" : "HTTP {$code}";

            return null;
        }

        $decoded = json_decode($raw, true);

        return is_array($decoded) ? $decoded : null;
    }
}
