<?php

declare(strict_types=1);

use App\Support\OpenBook\BlackwellThermDecode;
use PHPUnit\Framework\TestCase;

final class BlackwellThermDecodeTest extends TestCase
{
    public function testDecodeValidQ88(): void
    {
        // 70.5 °C => 0x4680 with 0x4000 header
        $raw = 0x40004680;
        $this->assertEqualsWithDelta(70.5, BlackwellThermDecode::decodeQ88($raw), 0.01);
    }

    public function testRejectLockAndBadHeader(): void
    {
        $this->assertNull(BlackwellThermDecode::decodeQ88(0x4000FF00));
        $this->assertNull(BlackwellThermDecode::decodeQ88(0x00004680));
        $this->assertNull(BlackwellThermDecode::decodeQ88(0x4000 | (140 * 256)));
    }

    public function testSelectHotSpotPrefersMatchingS5(): void
    {
        $r = BlackwellThermDecode::selectHotSpot([72.0, 80.0, 75.0, 90.0, 90.0, 68.0]);
        $this->assertSame(90.0, $r['hotspot']);
        $this->assertSame(18.0, $r['spread']);

        $r2 = BlackwellThermDecode::selectHotSpot([72.0, 80.0, 75.0, 91.0, null, 68.0]);
        $this->assertSame(91.0, $r2['hotspot']);
    }

    public function testPlausibleHotSpotRejectsLockAndCoreClone(): void
    {
        $this->assertFalse(BlackwellThermDecode::isPlausibleHotSpot(255.0));
        $this->assertFalse(BlackwellThermDecode::isPlausibleHotSpot(43.0, 43.0, true));
        $this->assertTrue(BlackwellThermDecode::isPlausibleHotSpot(98.5, 68.0, true));
        $this->assertTrue(BlackwellThermDecode::isPlausibleHotSpot(72.1, 72.0, false));
    }
}
