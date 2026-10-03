<?php

namespace Tests\Unit;

use App\Support\Pricing\PricingService;
use App\Support\Pricing\PricingSettings;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/** Fixture yang sama dipakai test Flutter, sehingga tablet & server pasti menghitung sama. */
class PricingServiceTest extends TestCase
{
    public static function fixtures(): iterable
    {
        // Repo (CI) atau mount /docs (Docker dev).
        $path = collect([dirname(__DIR__, 3).'/docs', '/docs'])
            ->map(fn (string $dir) => $dir.'/pricing-fixtures.json')
            ->first(fn (string $p) => is_file($p));
        foreach (json_decode(file_get_contents($path), true)['cases'] as $case) {
            yield $case['name'] => [$case];
        }
    }

    #[DataProvider('fixtures')]
    public function test_fixture(array $case): void
    {
        $s = $case['settings'];
        $result = (new PricingService)->calculate(
            $case['items'],
            $case['order_discount'],
            new PricingSettings($s['service_bp'], $s['tax_bp'], $s['rounding_unit']),
        );

        $this->assertSame($case['expected'], $result->toArray());
    }

    public function test_rejects_amount_discount_larger_than_line(): void
    {
        $this->expectException(InvalidArgumentException::class);

        (new PricingService)->calculate(
            [['unit_price' => 13000, 'qty' => 1, 'discount' => ['type' => 'amount', 'value' => 13001]]],
            null,
            new PricingSettings,
        );
    }
}
