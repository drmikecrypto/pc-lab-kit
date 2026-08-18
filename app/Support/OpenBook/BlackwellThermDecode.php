<?php

declare(strict_types=1);

namespace App\Support\OpenBook;

/**
 * Blackwell THERM Q8.8 decode — mirrors PcLabHwMon BlackwellTherm.cs for tests
 * and any server-side validation of open-book payloads.
 *
 * @see docs/OPEN_BOOK_SENSORS.md
 */
final class BlackwellThermDecode
{
    public const VALID_FLAG = 0x40000000;
    public const TEMP_HEADER_MASK = 0xFFFF0000;
    public const LOCK_SENTINEL = 0xFF00;
    public const TEMP_MIN_C = 0.0;
    public const TEMP_MAX_C = 130.0;

    public static function decodeQ88(int $raw): ?float
    {
        $raw = $raw & 0xFFFFFFFF;
        if (($raw & self::TEMP_HEADER_MASK) !== self::VALID_FLAG) {
            return null;
        }
        $lower = $raw & 0xFFFF;
        if ($lower === self::LOCK_SENTINEL) {
            return null;
        }
        $c = $lower / 256.0;
        if ($c <= self::TEMP_MIN_C || $c >= self::TEMP_MAX_C) {
            return null;
        }

        return round($c, 3);
    }

    /**
     * @param list<float|null> $channels S1..S6
     * @return array{hotspot: float|null, spread: float|null}
     */
    public static function selectHotSpot(array $channels): array
    {
        $spatial = [];
        for ($i = 0; $i < 4; $i++) {
            if (isset($channels[$i]) && is_numeric($channels[$i])) {
                $spatial[] = (float) $channels[$i];
            }
        }
        if ($spatial === []) {
            return ['hotspot' => null, 'spread' => null];
        }
        $maxSpatial = max($spatial);
        $spread = round($maxSpatial - min($spatial), 2);
        $s5 = isset($channels[4]) && is_numeric($channels[4]) ? (float) $channels[4] : null;
        $hotspot = ($s5 !== null && abs($s5 - $maxSpatial) < 0.15) ? $s5 : $maxSpatial;

        return ['hotspot' => round($hotspot, 3), 'spread' => $spread];
    }

    /** Reject NVAPI lock / nonsense hotspot readings. */
    public static function isPlausibleHotSpot(?float $hotSpotC, ?float $coreC = null, bool $blackwellHint = false): bool
    {
        if ($hotSpotC === null || $hotSpotC < 5.0 || $hotSpotC >= 250.0) {
            return false;
        }
        if ($blackwellHint && $coreC !== null && abs($hotSpotC - $coreC) < 0.25) {
            return false;
        }

        return $hotSpotC < self::TEMP_MAX_C;
    }
}
