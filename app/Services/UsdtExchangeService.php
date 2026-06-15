<?php

declare(strict_types=1);

namespace App\Services;

/**
 * USDT/TMN rate from Wallex — refreshed on a schedule (cron), not on page views.
 * @see https://api.wallex.ir/v1/markets
 */
class UsdtExchangeService
{
    public const LEGACY_USD_TOMAN = 200_000;
    public const WEEK_SECONDS = 604_800;

    private string $cacheFile;
    private int $cacheTtl;
    private string $marketsUrl;
    private int $fallbackRate;

    public function __construct(?array $config = null)
    {
        $app = $config ?? (require dirname(__DIR__, 2) . '/config/app.php')['exchange'] ?? [];
        $cachePath = dirname(__DIR__, 2) . '/storage/cache';
        $this->cacheFile = $cachePath . '/wallex_usdt_toman.json';
        $this->cacheTtl = max(self::WEEK_SECONDS, (int) ($app['cache_ttl_seconds'] ?? self::WEEK_SECONDS));
        $this->marketsUrl = (string) ($app['wallex_markets_url'] ?? 'https://api.wallex.ir/v1/markets');
        $this->fallbackRate = max(1, (int) ($app['fallback_usdt_toman'] ?? self::LEGACY_USD_TOMAN));
    }

    /** Read cached rate only — never hits Wallex (use refreshRate() from cron). */
    public function getQuote(): array
    {
        $cached = $this->readCache(true);
        if ($cached !== null) {
            $fetchedAt = strtotime($cached['fetched_at']);
            $age = $fetchedAt > 0 ? time() - $fetchedAt : PHP_INT_MAX;
            $cached['stale'] = $age > $this->cacheTtl;

            return $cached;
        }

        return [
            'rate' => $this->fallbackRate,
            'source' => 'fallback',
            'fetched_at' => date('c'),
            'stale' => true,
        ];
    }

    public function getRate(): int
    {
        return $this->getQuote()['rate'];
    }

    /** Fetch Wallex and update cache. Call from cron (weekly or after sync). */
    public function refreshRate(): array
    {
        $live = $this->fetchFromWallex();
        if ($live !== null) {
            $this->writeCache($live);

            return [
                'rate' => $live,
                'source' => 'wallex',
                'fetched_at' => date('c'),
                'stale' => false,
                'refreshed' => true,
            ];
        }

        $cached = $this->readCache(true);
        if ($cached !== null) {
            return array_merge($cached, ['stale' => true, 'refreshed' => false]);
        }

        return [
            'rate' => $this->fallbackRate,
            'source' => 'fallback',
            'fetched_at' => date('c'),
            'stale' => true,
            'refreshed' => false,
        ];
    }

    /** Refresh only when cache is missing or older than TTL. */
    public function refreshRateIfDue(): array
    {
        $cached = $this->readCache(true);
        if ($cached !== null) {
            $fetchedAt = strtotime($cached['fetched_at']);
            if ($fetchedAt > 0 && (time() - $fetchedAt) < $this->cacheTtl) {
                return array_merge($cached, ['stale' => false, 'refreshed' => false]);
            }
        }

        return $this->refreshRate();
    }

    public function usdToToman(float $usd, ?int $rate = null): int
    {
        if ($usd <= 0) {
            return 0;
        }

        return (int) round($usd * ($rate ?? $this->getRate()));
    }

    private function fetchFromWallex(): ?int
    {
        $ctx = stream_context_create([
            'http' => [
                'timeout' => 8,
                'header' => "Accept: application/json\r\nUser-Agent: PCVerse/1.0\r\n",
            ],
            'ssl' => [
                'verify_peer' => true,
                'verify_peer_name' => true,
            ],
        ]);

        $raw = @file_get_contents($this->marketsUrl, false, $ctx);
        if ($raw === false || $raw === '') {
            return null;
        }

        $data = \App\json_decode_assoc((string) $raw, '{}');
        if ($data === []) {
            return null;
        }

        $stats = $data['result']['symbols']['USDTTMN']['stats'] ?? null;
        if (!is_array($stats)) {
            return null;
        }

        foreach (['lastPrice', 'askPrice', 'bidPrice'] as $field) {
            if (!empty($stats[$field])) {
                $rate = (int) round((float) $stats[$field]);
                if ($rate > 0) {
                    return $rate;
                }
            }
        }

        return null;
    }

    /** @return array{rate: int, source: string, fetched_at: string}|null */
    private function readCache(bool $allowExpired = false): ?array
    {
        if (!is_file($this->cacheFile)) {
            return null;
        }

        $payload = \App\json_decode_assoc((string) file_get_contents($this->cacheFile), '{}');
        if (empty($payload['rate'])) {
            return null;
        }

        $fetchedAt = strtotime((string) ($payload['fetched_at'] ?? ''));
        if (!$allowExpired && $fetchedAt > 0 && (time() - $fetchedAt) > $this->cacheTtl) {
            return null;
        }

        return [
            'rate' => (int) $payload['rate'],
            'source' => (string) ($payload['source'] ?? 'wallex'),
            'fetched_at' => (string) ($payload['fetched_at'] ?? date('c')),
        ];
    }

    private function writeCache(int $rate): void
    {
        $dir = dirname($this->cacheFile);
        if (!is_dir($dir)) {
            @mkdir($dir, 0755, true);
        }

        @file_put_contents($this->cacheFile, json_encode([
            'rate' => $rate,
            'source' => 'wallex',
            'fetched_at' => date('c'),
        ], JSON_UNESCAPED_UNICODE));
    }
}
