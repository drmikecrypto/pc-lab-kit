<?php

declare(strict_types=1);

namespace App\Services;

use App\Database;
use PDO;

/**
 * Benchmark row prices:
 * - Provider/partner: listing.price_toman from parts synced via cron (affiliate_url listings only)
 * - Everything else: USD × weekly Wallex USDT rate (cache rebuilt by cron)
 *
 * Catalog index is built by cron/sync_providers.php — not on page views.
 */
class BenchmarkPricingService
{
    private UsdtExchangeService $exchange;
    private BenchmarkDatasetService $dataset;
    private PDO $db;
    private string $indexCacheFile;

    /** @var array<string, array>|null */
    private ?array $indexMemory = null;

    public function __construct(
        ?UsdtExchangeService $exchange = null,
        ?BenchmarkDatasetService $dataset = null,
        ?PDO $db = null
    ) {
        $this->exchange = $exchange ?? new UsdtExchangeService();
        $this->dataset = $dataset ?? new BenchmarkDatasetService();
        $this->db = $db ?? Database::connection();
        $this->indexCacheFile = dirname(__DIR__, 2) . '/storage/cache/benchmark_catalog_prices.json';
    }

    /** @return array{rate: int, source: string, fetched_at: string, stale: bool} */
    public function quote(): array
    {
        return $this->exchange->getQuote();
    }

    /** @param list<array> $rows */
    public function applyToRows(array $rows): array
    {
        $rate = $this->exchange->getRate();
        $index = $this->catalogPriceIndex();

        foreach ($rows as &$row) {
            $row = $this->applyToRow($row, $rate, $index);
        }
        unset($row);

        return $rows;
    }

    /** @param array<string, array> $index */
    public function applyToRow(array $row, int $rate, array $index): array
    {
        $norm = (string) ($row['name_norm'] ?? $this->dataset->normalizeName((string) ($row['name'] ?? '')));
        $hit = $index[$norm] ?? null;

        if ($hit === null && !empty($row['name'])) {
            $alt = $this->dataset->normalizeName((string) $row['name']);
            $hit = $index[$alt] ?? null;
        }

        if ($hit !== null) {
            $row['price_toman'] = (int) $hit['price_toman'];
            $row['price_source'] = (string) $hit['price_source'];
            $row['price_part_id'] = (int) $hit['part_id'];
            $row['price_listing_id'] = (int) ($hit['listing_id'] ?? 0);
            $row['price_provider'] = $hit['provider_name'] ?? null;
            $row['price_synced_at'] = $hit['synced_at'] ?? null;
            $row['price_live'] = false;
        } else {
            $usd = (float) ($row['price_usd'] ?? 0);
            if ($usd <= 0 && !empty($row['price_toman'])) {
                $usd = ((float) $row['price_toman']) / UsdtExchangeService::LEGACY_USD_TOMAN;
            }
            if ($usd > 0) {
                $row['price_toman'] = $this->exchange->usdToToman($usd, $rate);
                $row['price_source'] = 'usdt';
                $row['price_live'] = false;
            }
        }

        $row['usdt_rate'] = $rate;

        return $row;
    }

    /**
     * Read pre-built index (from cron). Never rebuilds on web requests.
     * @return array<string, array>
     */
    public function catalogPriceIndex(): array
    {
        if ($this->indexMemory !== null) {
            return $this->indexMemory;
        }

        return $this->indexMemory = $this->readIndexCache() ?? [];
    }

    /**
     * Rebuild catalog ↔ benchmark price map from cron-synced listings.
     * @return array{count: int, built_at: string}
     */
    public function rebuildCatalogIndex(): array
    {
        $index = $this->buildCatalogPriceIndex();
        $this->writeIndexCache($index);
        $this->indexMemory = $index;

        return [
            'count' => count($index),
            'built_at' => date('c'),
        ];
    }

    /** @return array<string, array>|null */
    private function readIndexCache(): ?array
    {
        if (!is_file($this->indexCacheFile)) {
            return null;
        }

        $payload = \App\json_decode_assoc((string) file_get_contents($this->indexCacheFile), '{}');
        if (!isset($payload['index']) || !is_array($payload['index'])) {
            return null;
        }

        return $payload['index'];
    }

    /**
     * Only listings with affiliate_url — same set ProviderSyncService::syncAll updates.
     * @return array<string, array>
     */
    private function buildCatalogPriceIndex(): array
    {
        $partnerFlag = $this->providerPartnerSqlExpr();

        $sql = "SELECT p.*, c.slug AS category_slug,
                       l.id AS listing_id, l.price_toman, l.stock, l.updated_at AS listing_updated_at,
                       pr.name AS provider_name, pr.id AS provider_id, {$partnerFlag} AS is_partner
                FROM parts p
                JOIN categories c ON c.id = p.category_id
                JOIN listings l ON l.part_id = p.id
                    AND l.status = 'live'
                    AND l.stock > 0
                    AND l.affiliate_url IS NOT NULL
                    AND l.affiliate_url != ''
                JOIN providers pr ON pr.id = l.provider_id AND pr.status = 'approved'
                WHERE c.slug IN ('cpu', 'gpu', 'ram', 'memory', 'storage')
                ORDER BY p.id, is_partner DESC, l.price_toman ASC";

        try {
            $rows = $this->db->query($sql)->fetchAll();
        } catch (\Throwable $e) {
            error_log('Benchmark catalog price index failed: ' . $e->getMessage());

            return [];
        }

        if ($rows === false) {
            return [];
        }

        /** @var array<int, array{part: array, listings: list<array>}> $grouped */
        $grouped = [];
        foreach ($rows as $row) {
            $pid = (int) $row['id'];
            if (!isset($grouped[$pid])) {
                $grouped[$pid] = ['part' => $row, 'listings' => []];
            }
            $grouped[$pid]['listings'][] = $row;
        }

        $index = [];
        foreach ($grouped as $bundle) {
            $part = $bundle['part'];
            $listings = $bundle['listings'];

            $partner = null;
            $cheapest = null;
            foreach ($listings as $l) {
                if ((int) ($l['is_partner'] ?? 0) === 1) {
                    if ($partner === null || (int) $l['price_toman'] < (int) $partner['price_toman']) {
                        $partner = $l;
                    }
                }
                if ($cheapest === null || (int) $l['price_toman'] < (int) $cheapest['price_toman']) {
                    $cheapest = $l;
                }
            }

            $chosen = $partner ?? $cheapest;
            if ($chosen === null) {
                continue;
            }

            $match = $this->dataset->matchPart($part);
            if ($match === null || empty($match['name'])) {
                continue;
            }

            $key = $this->dataset->normalizeName((string) $match['name']);
            if ($key === '') {
                continue;
            }

            $entry = [
                'price_toman' => (int) $chosen['price_toman'],
                'price_source' => $partner !== null ? 'partner' : 'provider',
                'part_id' => (int) $part['id'],
                'listing_id' => (int) $chosen['listing_id'],
                'provider_name' => (string) ($chosen['provider_name'] ?? ''),
                'synced_at' => (string) ($chosen['listing_updated_at'] ?? ''),
            ];

            if (!isset($index[$key]) || $this->isBetterCatalogPrice($entry, $index[$key])) {
                $index[$key] = $entry;
            }
        }

        return $index;
    }

    /** @param array{price_source: string, price_toman: int} $candidate @param array{price_source: string, price_toman: int} $existing */
    private function isBetterCatalogPrice(array $candidate, array $existing): bool
    {
        $rank = ['partner' => 3, 'provider' => 2, 'usdt' => 1];
        $cRank = $rank[$candidate['price_source']] ?? 0;
        $eRank = $rank[$existing['price_source']] ?? 0;
        if ($cRank !== $eRank) {
            return $cRank > $eRank;
        }

        return (int) $candidate['price_toman'] < (int) $existing['price_toman'];
    }

    /** @param array<string, array> $index */
    private function writeIndexCache(array $index): void
    {
        $dir = dirname($this->indexCacheFile);
        if (!is_dir($dir)) {
            @mkdir($dir, 0755, true);
        }

        @file_put_contents($this->indexCacheFile, json_encode([
            'built_at' => date('c'),
            'source' => 'provider_sync_cron',
            'index' => $index,
        ], JSON_UNESCAPED_UNICODE));
    }

    private function providerPartnerSqlExpr(): string
    {
        $cols = $this->providerColumns();
        if (in_array('is_starred', $cols, true)) {
            return 'COALESCE(pr.is_starred, 0)';
        }
        if (in_array('featured', $cols, true)) {
            return 'COALESCE(pr.featured, 0)';
        }

        return '0';
    }

    /** @return list<string> */
    private function providerColumns(): array
    {
        static $cols = null;
        if ($cols !== null) {
            return $cols;
        }

        try {
            $driver = (string) $this->db->getAttribute(PDO::ATTR_DRIVER_NAME);
            if ($driver === 'sqlite') {
                $rows = $this->db->query('PRAGMA table_info(providers)')->fetchAll();
                $cols = array_map(static fn ($r) => (string) ($r['name'] ?? ''), $rows);
            } else {
                $rows = $this->db->query('SHOW COLUMNS FROM providers')->fetchAll();
                $cols = array_map(static fn ($r) => (string) ($r['Field'] ?? ''), $rows);
            }
        } catch (\Throwable $e) {
            $cols = ['featured'];
        }

        return $cols;
    }
}
