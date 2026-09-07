<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Compact TOON-inspired serializer for LLM context.
 * Flatter than pretty JSON — fewer braces/quotes, shorter keys, ~40–60% fewer tokens.
 *
 * Spec: tabular rows + key=value lines. Intentionally simple (no external package).
 */
class ToonSerializer
{
    /**
     * Encode a nested array/object into a compact TOON string.
     *
     * @param array<string, mixed>|list<mixed> $data
     */
    public function encode(array $data, string $root = 'ctx'): string
    {
        $lines = [];
        $this->encodeNode($root, $data, $lines, 0);

        return implode("\n", $lines);
    }

    /**
     * @param array<string, mixed>|list<mixed>|scalar|null $value
     * @param list<string> $lines
     */
    private function encodeNode(string $key, mixed $value, array &$lines, int $depth): void
    {
        $indent = str_repeat('  ', $depth);

        if ($value === null) {
            return;
        }

        if (is_bool($value)) {
            $lines[] = $indent . $key . '=' . ($value ? 'true' : 'false');

            return;
        }

        if (is_int($value) || is_float($value)) {
            $lines[] = $indent . $key . '=' . $this->num($value);

            return;
        }

        if (is_string($value)) {
            $v = trim($value);
            if ($v === '') {
                return;
            }
            $lines[] = $indent . $key . '=' . $this->quote($v);

            return;
        }

        if (!is_array($value)) {
            return;
        }

        if ($value === []) {
            return;
        }

        if ($this->isList($value)) {
            if ($this->isScalarList($value)) {
                $cells = array_map(fn ($v) => is_string($v) ? $this->quote((string) $v) : $this->num($v), $value);
                $lines[] = $indent . $key . '[' . count($value) . ']: ' . implode('|', $cells);

                return;
            }

            if ($this->isUniformAssocList($value)) {
                $keys = array_keys((array) $value[0]);
                $lines[] = $indent . $key . '[' . count($value) . ']{' . implode(',', $keys) . '}:';
                foreach ($value as $row) {
                    $cells = [];
                    foreach ($keys as $k) {
                        $cells[] = $this->cell($row[$k] ?? null);
                    }
                    $lines[] = $indent . '  ' . implode('|', $cells);
                }

                return;
            }

            $lines[] = $indent . $key . '[' . count($value) . ']:';
            foreach ($value as $i => $item) {
                $this->encodeNode((string) $i, $item, $lines, $depth + 1);
            }

            return;
        }

        $lines[] = $indent . $key . ':';
        foreach ($value as $k => $v) {
            $this->encodeNode((string) $k, $v, $lines, $depth + 1);
        }
    }

    private function cell(mixed $v): string
    {
        if ($v === null) {
            return '-';
        }
        if (is_bool($v)) {
            return $v ? 'true' : 'false';
        }
        if (is_int($v) || is_float($v)) {
            return $this->num($v);
        }
        if (is_array($v)) {
            return $this->quote(json_encode($v, JSON_UNESCAPED_UNICODE));
        }

        return $this->quote((string) $v);
    }

    private function num(int|float $n): string
    {
        if (is_int($n)) {
            return (string) $n;
        }
        $s = rtrim(rtrim(sprintf('%.4f', $n), '0'), '.');

        return $s === '' ? '0' : $s;
    }

    private function quote(string $s): string
    {
        $s = str_replace(["\r", "\n", '|'], [' ', ' ', '/'], $s);
        if (str_contains($s, ' ') || str_contains($s, ':') || str_contains($s, '=')) {
            return '"' . str_replace('"', "'", $s) . '"';
        }

        return $s;
    }

    /** @param array<mixed> $arr */
    private function isList(array $arr): bool
    {
        return array_keys($arr) === range(0, count($arr) - 1);
    }

    /** @param list<mixed> $arr */
    private function isScalarList(array $arr): bool
    {
        foreach ($arr as $v) {
            if (is_array($v)) {
                return false;
            }
        }

        return true;
    }

    /** @param list<mixed> $arr */
    private function isUniformAssocList(array $arr): bool
    {
        if ($arr === [] || !is_array($arr[0]) || $this->isList($arr[0])) {
            return false;
        }
        $keys = array_keys($arr[0]);
        foreach ($arr as $row) {
            if (!is_array($row) || array_keys($row) !== $keys) {
                return false;
            }
            foreach ($row as $v) {
                if (is_array($v)) {
                    return false;
                }
            }
        }

        return true;
    }
}
