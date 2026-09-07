<?php

declare(strict_types=1);

namespace App\Support\OpenBook;

/**
 * AMD SMU / ADL junction decode stub — mirrors LHM ADL path for tests.
 *
 * @see docs/OPEN_BOOK_SENSORS.md
 */
final class AmdSmuDecode
{
    public const TEMP_MIN_C = 5.0;
    public const TEMP_MAX_C = 130.0;
    public const LOCK_SENTINEL = 0xFF;

    /** SMU-style fixed-point (1/256 °C) when MMIO path lands. */
    public static function decodeFixed256(int $raw): ?float
    {
        $raw = $raw & 0xFFFF;
        if ($raw === self::LOCK_SENTINEL || $raw === 0) {
            return null;
        }
        $c = $raw / 256.0;
        if ($c <= self::TEMP_MIN_C || $c >= self::TEMP_MAX_C) {
            return null;
        }

        return round($c, 3);
    }

    /**
     * @param list<float|null> $junctions
     * @return array{hotspot: float|null, spread: float|null}
     */
    public static function selectJunction(array $junctions): array
    {
        $valid = array_values(array_filter($junctions, static fn ($v) => $v !== null && is_numeric($v)));
        if ($valid === []) {
            return ['hotspot' => null, 'spread' => null];
        }
        $floats = array_map(static fn ($v) => (float) $v, $valid);
        $max = max($floats);

        return [
            'hotspot' => round($max, 2),
            'spread' => round($max - min($floats), 2),
        ];
    }

    public static function isPlausible(?float $c): bool
    {
        return $c !== null && $c >= self::TEMP_MIN_C && $c < 250.0;
    }
}
