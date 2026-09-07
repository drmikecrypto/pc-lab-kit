<?php

declare(strict_types=1);

use App\Support\OpenBook\AmdSmuDecode;
use App\Support\OpenBook\BlackwellThermDecode;
use App\Support\OpenBook\IntelPeciDecode;
use PHPUnit\Framework\TestCase;

final class OpenBookDecodersTest extends TestCase
{
    public function testIntelPeciPackageByte(): void
    {
        $this->assertEqualsWithDelta(72.0, IntelPeciDecode::decodePackageByte(72), 0.01);
        $this->assertNull(IntelPeciDecode::decodePackageByte(0));
        $this->assertNull(IntelPeciDecode::decodePackageByte(0xFE));

        $r = IntelPeciDecode::selectPackage([65, 72, 68]);
        $this->assertSame(72.0, $r['package']);
        $this->assertSame(7.0, $r['spread']);
    }

    public function testAmdSmuFixed256(): void
    {
        $raw = (int) (85.5 * 256);
        $this->assertEqualsWithDelta(85.5, AmdSmuDecode::decodeFixed256($raw), 0.05);
        $this->assertNull(AmdSmuDecode::decodeFixed256(0xFF));

        $r = AmdSmuDecode::selectJunction([70.0, 88.5, 75.0]);
        $this->assertSame(88.5, $r['hotspot']);
        $this->assertSame(18.5, $r['spread']);
    }

    /** @return list<array{hex: string, expected: float|null}> */
    public static function goldenBlackwellVectors(): array
    {
        return [
            ['hex' => '40004680', 'expected' => 70.5],
            ['hex' => '40005A00', 'expected' => 90.0],
            ['hex' => '4000FF00', 'expected' => null],
            ['hex' => '00004680', 'expected' => null],
        ];
    }

    /**
     * @dataProvider goldenBlackwellVectors
     */
    public function testGoldenBlackwellMmio(string $hex, ?float $expected): void
    {
        $raw = (int) hexdec($hex);
        if ($expected === null) {
            $this->assertNull(BlackwellThermDecode::decodeQ88($raw));
        } else {
            $this->assertEqualsWithDelta($expected, BlackwellThermDecode::decodeQ88($raw), 0.02);
        }
    }

    public function testRegisterCatalogFileExists(): void
    {
        $path = dirname(__DIR__, 2) . '/agent/pclab_probe/data/register-catalog.json';
        $this->assertFileExists($path);
        $data = json_decode((string) file_get_contents($path), true);
        $this->assertIsArray($data);
        $this->assertGreaterThanOrEqual(6, count($data['registers'] ?? []));
        $tags = $data['provenance_tags'] ?? [];
        $this->assertContains('blackwell_therm_mmio', $tags);
        $this->assertContains('intel_peci', $tags);
        $this->assertContains('adl', $tags);
    }
}
