<?php

namespace App\Services;

class BenchmarkService
{
    private BenchmarkDatasetService $dataset;

    public function __construct(?BenchmarkDatasetService $dataset = null)
    {
        $this->dataset = $dataset ?? new BenchmarkDatasetService();
    }

    public function analyze(array $selectedParts): array
    {
        $cpuScore = 0;
        $gpuScore = 0;
        $ramScore = 0;
        $storageScore = 0;
        $matches = [];

        foreach ($selectedParts as $p) {
            $slug = $p['category_slug'] ?? '';
            $score = (int) ($p['benchmark_score'] ?? 0);

            $match = $this->dataset->matchPart($p);
            if ($match) {
                $metricKey = $match['dataset'] ?? '';
                $primary = $this->primaryScoreFromMatch($match);
                if ($score <= 0 && $primary > 0) {
                    $score = $primary;
                }
                $matches[$slug] = [
                    'name' => $match['name'],
                    'score' => $primary,
                    'percentile' => $match['percentile'] ?? $this->dataset->scorePercentile((string) ($match['component'] ?? $slug), $primary),
                    'dataset' => $metricKey,
                ];
            }

            match ($slug) {
                'cpu' => $cpuScore = max($cpuScore, $score),
                'gpu' => $gpuScore = max($gpuScore, $score),
                'ram', 'memory' => $ramScore = max($ramScore, $score),
                'storage' => $storageScore = max($storageScore, $score),
                default => null,
            };
        }

        $cpuPct = $cpuScore > 0 ? $this->dataset->scorePercentile('cpu', $cpuScore) : 0;
        $gpuPct = $gpuScore > 0 ? $this->dataset->scorePercentile('gpu', $gpuScore) : 0;
        $ramPct = $ramScore > 0 ? min(100, (int) round($ramScore / 450)) : 0;
        $storagePct = $storageScore > 0 ? min(100, (int) round($storageScore / 10)) : 0;

        $overall = $cpuScore + $gpuScore + ($ramScore / 10) + ($storageScore / 100);
        $bottleneck = $this->bottleneck($cpuScore, $gpuScore, $cpuPct, $gpuPct);
        $tier = $this->performanceTier((int) $overall);
        $fps = $this->estimateFpsTiers($gpuScore, $cpuScore, $gpuPct);

        $gamingPct = ($gpuPct > 0 || $cpuPct > 0)
            ? min(100, (int) round($gpuPct * 0.72 + $cpuPct * 0.28))
            : 0;
        $workPct = ($cpuPct > 0 || $ramPct > 0 || $storagePct > 0)
            ? min(100, (int) round($cpuPct * 0.55 + $ramPct * 0.25 + $storagePct * 0.20))
            : 0;

        $balancePct = $this->balanceScore($cpuPct, $gpuPct, $ramPct, $storagePct);
        $valuePct = $this->valueScore($selectedParts, $cpuScore + $gpuScore);

        $geekNotes = $this->geekNotes($cpuScore, $gpuScore, $ramScore, $storageScore, $bottleneck, $matches);

        $overallInt = (int) round($overall);

        return [
            'cpu_score' => $cpuScore,
            'gpu_score' => $gpuScore,
            'ram_score' => $ramScore,
            'storage_score' => $storageScore,
            'cpu_percentile' => $cpuPct,
            'gpu_percentile' => $gpuPct,
            'ram_percentile' => $ramPct,
            'storage_percentile' => $storagePct,
            'overall_score' => $overallInt,
            'gaming_score_percent' => $gamingPct,
            'workstation_score_percent' => $workPct,
            'balance_percent' => $balancePct,
            'value_percent' => $valuePct,
            'bottleneck' => $bottleneck,
            'fps_estimates' => $fps,
            'tier' => $tier,
            'geek_notes' => $geekNotes,
            'matches' => $matches,
            'radar' => [
                ['axis' => 'CPU', 'value' => $cpuPct, 'score' => $cpuScore],
                ['axis' => 'GPU', 'value' => $gpuPct, 'score' => $gpuScore],
                ['axis' => 'RAM', 'value' => $ramPct, 'score' => $ramScore],
                ['axis' => 'Storage', 'value' => $storagePct, 'score' => $storageScore],
                ['axis' => 'Balance', 'value' => $balancePct, 'score' => 0],
                ['axis' => 'Value', 'value' => $valuePct, 'score' => 0],
            ],
            'benchmark_board' => $this->makeBenchmarkBoard(
                $tier,
                $overallInt,
                $gamingPct,
                $workPct,
                $balancePct,
                $valuePct,
                $cpuScore,
                $gpuScore,
                $ramScore,
                $storageScore,
                $bottleneck,
                $fps
            ),
        ];
    }

    /**
     * @param array<string, mixed> $tier
     * @param array<string, mixed> $bottleneck
     * @param list<array<string, mixed>> $fps
     * @return array<string, mixed>
     */
    private function makeBenchmarkBoard(
        array $tier,
        int $overallInt,
        int $gamingPct,
        int $workPct,
        int $balancePct,
        int $valuePct,
        int $cpuScore,
        int $gpuScore,
        int $ramScore,
        int $storageScore,
        array $bottleneck,
        array $fps
    ): array {
        $tierName = (string) ($tier['name'] ?? '');
        $headline = $overallInt > 0
            ? "{$tierName} — امتیاز ترکیبی ~" . number_format($overallInt)
            : 'قطعات اصلی را کامل کنید تا تابلو بنچمارک فعال شود.';

        $fps1080 = $fps[0] ?? null;

        return [
            'headline_fa' => $headline,
            'tier' => $tier,
            'overall_score' => $overallInt,
            'bars' => [
                ['key' => 'gaming', 'label_fa' => 'جهت بازی', 'pct' => $gamingPct, 'tone' => 'primary'],
                ['key' => 'work', 'label_fa' => 'کار سنگین', 'pct' => $workPct, 'tone' => 'blue'],
                ['key' => 'balance', 'label_fa' => 'تعادل قطعات', 'pct' => $balancePct, 'tone' => 'cyan'],
                ['key' => 'value', 'label_fa' => 'ارزش نسبی (بنچ/قیمت)', 'pct' => $valuePct, 'tone' => 'green'],
            ],
            'scores' => [
                ['label_fa' => 'CPU PassMark', 'score' => $cpuScore],
                ['label_fa' => 'GPU G3D', 'score' => $gpuScore],
                ['label_fa' => 'رم (شاخص)', 'score' => $ramScore],
                ['label_fa' => 'ذخیره‌ساز (شاخص)', 'score' => $storageScore],
            ],
            'bottleneck_one_liner' => (string) ($bottleneck['label_fa'] ?? ''),
            'fps_highlight' => is_array($fps1080) ? $fps1080 : null,
        ];
    }

    private function primaryScoreFromMatch(array $match): int
    {
        foreach (['mark', 'bench', 'value'] as $k) {
            $v = (int) ($match[$k] ?? 0);
            if ($v > 0) {
                return $v;
            }
        }

        return 0;
    }

    private function balanceScore(int $cpu, int $gpu, int $ram, int $storage): int
    {
        $parts = array_filter([$cpu, $gpu, $ram, $storage], fn ($v) => $v > 0);
        if (count($parts) < 2) {
            return 50;
        }
        $avg = array_sum($parts) / count($parts);
        $variance = 0.0;
        foreach ($parts as $p) {
            $variance += ($p - $avg) ** 2;
        }
        $std = sqrt($variance / count($parts));

        return (int) max(20, min(100, round(100 - ($std * 1.2))));
    }

    private function valueScore(array $parts, int $totalBench): int
    {
        $totalPrice = 0;
        foreach ($parts as $p) {
            $totalPrice += (int) ($p['min_price'] ?? $p['display_price'] ?? 0);
        }
        if ($totalPrice <= 0 || $totalBench <= 0) {
            return 0;
        }
        $millions = $totalPrice / 1_000_000;
        $raw = $totalBench / max(0.1, $millions);

        return (int) min(100, round($raw / 15));
    }

    private function bottleneck(int $cpu, int $gpu, int $cpuPct, int $gpuPct): array
    {
        if ($cpu <= 0 || $gpu <= 0) {
            return [
                'type' => 'unknown',
                'percent' => 0,
                'label_fa' => 'برای تحلیل گلوگاه، CPU و GPU را انتخاب کنید.',
            ];
        }

        $ratio = $cpu / max($gpu, 1);
        if ($ratio < 0.55 || ($cpuPct > 0 && $gpuPct > 0 && $cpuPct < $gpuPct - 18)) {
            $pct = (int) min(99, max(10, $gpuPct - $cpuPct));
            return [
                'type' => 'cpu',
                'percent' => $pct,
                'label_fa' => "گلوگاه پردازنده ≈ {$pct}% — GPU از PassMark قوی‌تر از CPU است.",
            ];
        }
        if ($ratio > 1.8 || ($cpuPct > 0 && $gpuPct > 0 && $gpuPct < $cpuPct - 18)) {
            $pct = (int) min(99, max(10, $cpuPct - $gpuPct));
            return [
                'type' => 'gpu',
                'percent' => $pct,
                'label_fa' => "گلوگاه گرافیک ≈ {$pct}% — CPU از PassMark قوی‌تر از GPU است.",
            ];
        }

        return [
            'type' => 'balanced',
            'percent' => max(3, (int) abs($cpuPct - $gpuPct) / 2),
            'label_fa' => 'تعادل خوب بین CPU و GPU بر اساس داده PassMark.',
        ];
    }

    private function estimateFpsTiers(int $gpu, int $cpu, int $gpuPct): array
    {
        $base = $gpuPct > 0
            ? (int) round(25 + ($gpuPct * 1.1))
            : (int) round(($gpu * 0.7 + $cpu * 0.3) / 100);

        return [
            ['game' => 'بازی AAA (1080p بالا)', 'fps' => max(18, $base - 15), 'tier' => $this->fpsTier($base - 15)],
            ['game' => 'بازی AAA (1440p)', 'fps' => max(12, (int) ($base * 0.68) - 10), 'tier' => $this->fpsTier((int) ($base * 0.68) - 10)],
            ['game' => 'بازی AAA (4K)', 'fps' => max(8, (int) ($base * 0.42) - 5), 'tier' => $this->fpsTier((int) ($base * 0.42) - 5)],
            ['game' => 'eSports (1080p)', 'fps' => max(90, $base + 55), 'tier' => 'excellent'],
            ['game' => 'شبیه‌ساز / استراتژی', 'fps' => max(45, $base + 12), 'tier' => $this->fpsTier($base + 12)],
        ];
    }

    private function fpsTier(int $fps): string
    {
        return match (true) {
            $fps >= 120 => 'excellent',
            $fps >= 60 => 'great',
            $fps >= 30 => 'playable',
            default => 'low',
        };
    }

    private function performanceTier(int $overall): array
    {
        $slug = match (true) {
            $overall >= 8500 => 'legend',
            $overall >= 6500 => 'pro',
            $overall >= 4500 => 'gaming',
            $overall >= 2500 => 'daily',
            $overall > 0 => 'entry',
            default => 'none',
        };

        return match ($slug) {
            'legend' => ['name' => 'اسطوره', 'slug' => 'legend', 'color' => 'purple'],
            'pro' => ['name' => 'گیمینگ حرفه‌ای', 'slug' => 'pro', 'color' => 'cyan'],
            'gaming' => ['name' => 'گیمینگ میان‌رده', 'slug' => 'gaming', 'color' => 'green'],
            'daily' => ['name' => 'روزمره / اداری', 'slug' => 'daily', 'color' => 'yellow'],
            'entry' => ['name' => 'ورودی', 'slug' => 'entry', 'color' => 'gray'],
            default => ['name' => '—', 'slug' => 'none', 'color' => 'gray'],
        };
    }

    private function geekNotes(int $cpu, int $gpu, int $ram, int $storage, array $bottleneck, array $matches): array
    {
        $notes = [];
        if ($cpu > 0) {
            $notes[] = 'رتبه CPU در PassMark: ' . number_format($cpu);
        }
        if ($gpu > 0) {
            $notes[] = 'قدرت گرافیکی G3D Mark: ' . number_format($gpu);
        }
        foreach ($matches as $slug => $m) {
            if (($m['percentile'] ?? 0) >= 90) {
                $notes[] = "⭐ {$m['name']} در صدک {$m['percentile']} قرار دارد — انتخاب فлаг‌شip.";
            }
        }
        if ($ram > 0 && $ram < 4000) {
            $notes[] = 'رم ممکن است در بازی‌های جدید محدودکننده باشد — ۱۶GB+ توصیه می‌شود.';
        }
        if ($storage > 0 && $storage < 3500) {
            $notes[] = 'SSD سریع‌تر زمان بارگذاری و stutter را کم می‌کند.';
        }
        if ($bottleneck['type'] === 'cpu') {
            $notes[] = 'برای استریم/رندر، ارتقای CPU اولویت بالاتری دارد.';
        }
        if ($bottleneck['type'] === 'gpu') {
            $notes[] = 'برای رزولوشن بالاتر، GPU قوی‌تر بیشترین اثر را دارد.';
        }

        return $notes;
    }
}
