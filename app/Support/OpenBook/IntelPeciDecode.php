<?php

declare(strict_types=1);

namespace App\Support\OpenBook;

/**
 * Intel PECI / package temperature decode stub — mirrors future HwMon path.
 *
 * @see docs/OPEN_BOOK_SENSORS.md
 */
final class IntelPeciDecode
{
    public const TEMP_MIN_C = 5.0;
    public const TEMP_MAX_C = 125.0;

    /** PECI raw byte (0–255) → °C for common desktop parts. */
    public static function decodePackageByte(int $raw): ?float
    {
        $raw = $raw & 0xFF;
        if ($raw === 0 || $raw >= 0xFE) {
            return null;
        }
        $c = (float) $raw;

        return ($c >= self::TEMP_MIN_C && $c <= self::TEMP_MAX_C) ? round($c, 2) : null;
    }

    /**
     * @param list<int|null> $dies
     * @return array{package: float|null, spread: float|null}
     */
    public static function selectPackage(array $dies): array
    {
        $valid = array_values(array_filter($dies, static fn ($v) => $v !== null && is_numeric($v)));
        if ($valid === []) {
            return ['package' => null, 'spread' => null];
        }
        $floats = array_map(static fn ($v) => (float) $v, $valid);

        return [
            'package' => round(max($floats), 2),
            'spread' => round(max($floats) - min($floats), 2),
        ];
    }

    public static function isPlausible(?float $c): bool
    {
        return $c !== null && $c >= self::TEMP_MIN_C && $c <= self::TEMP_MAX_C;
    }
}
