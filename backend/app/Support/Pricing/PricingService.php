<?php

namespace App\Support\Pricing;

use InvalidArgumentException;

/**
 * Mesin harga — sumber kebenaran. App Flutter memakai cerminannya (lib/features/cart/pricing.dart);
 * keduanya diuji dengan fixture yang sama: docs/pricing-fixtures.json.
 *
 * Urutan: baris (diskon item) → subtotal → diskon order → service → pajak → pembulatan.
 * Semua integer rupiah; persen dalam basis poin (1000 = 10%).
 *
 * Harga "termasuk pajak" / "termasuk service" (diatur terpisah): bagian itu dihitung mundur dari harga
 * menu dan TIDAK menambah total; bagian yang tidak termasuk ditambahkan seperti biasa. Pajak selalu
 * dikenakan atas (harga bersih + service).
 */
class PricingService
{
    /**
     * @param  list<array{unit_price: int, qty: int, discount?: array{type: string, value: int}|null}>  $items
     * @param  array{type: string, value: int}|null  $orderDiscount
     */
    public function calculate(array $items, ?array $orderDiscount, PricingSettings $settings): PricingResult
    {
        $lines = [];
        $lineDiscounts = [];

        foreach ($items as $i => $item) {
            if ($item['qty'] < 1 || $item['unit_price'] < 0) {
                throw new InvalidArgumentException("Item {$i}: qty/harga tidak valid.");
            }
            $gross = $item['unit_price'] * $item['qty'];
            $discount = self::discount($gross, $item['discount'] ?? null, "items.{$i}.discount");
            $lineDiscounts[] = $discount;
            $lines[] = $gross - $discount;
        }

        $subtotal = array_sum($lines);
        $orderDiscountAmount = self::discount($subtotal, $orderDiscount, 'order_discount');
        $base = $subtotal - $orderDiscountAmount;

        [$service, $tax, $added] = self::serviceAndTax($base, $settings);
        $beforeRounding = $base + $added;

        $grand = $settings->roundingUnit > 0
            ? self::halfUp($beforeRounding, $settings->roundingUnit) * $settings->roundingUnit
            : $beforeRounding;

        return new PricingResult(
            lines: $lines,
            lineDiscounts: $lineDiscounts,
            subtotal: $subtotal,
            itemDiscountTotal: array_sum($lineDiscounts),
            orderDiscount: $orderDiscountAmount,
            serviceTotal: $service,
            taxTotal: $tax,
            rounding: $grand - $beforeRounding,
            grandTotal: $grand,
            serviceBp: $settings->serviceBp,
            taxBp: $settings->taxBp,
            serviceInclusive: $settings->serviceInclusive,
            taxInclusive: $settings->taxInclusive,
        );
    }

    /**
     * @return array{0: int, 1: int, 2: int} [service, pajak, tambahan di atas harga menu]
     */
    private static function serviceAndTax(int $base, PricingSettings $s): array
    {
        $S = $s->serviceBp;
        $T = $s->taxBp;

        // Pajak yang sudah ada di dalam harga menu.
        $taxIncluded = $s->taxInclusive ? self::halfUp($base * $T, 10000 + $T) : 0;
        $afterTax = $base - $taxIncluded;

        if ($s->serviceInclusive) {
            $serviceIncluded = self::halfUp($afterTax * $S, 10000 + $S);
            $serviceAdded = 0;
        } else {
            $serviceIncluded = 0;
            $serviceAdded = self::halfUp($afterTax * $S, 10000);
        }

        // Pajak tambahan: harga sudah termasuk pajak → hanya atas service yang ditambahkan;
        // tidak termasuk → atas seluruh (harga + service tambahan).
        $taxAdded = $s->taxInclusive
            ? self::halfUp($serviceAdded * $T, 10000)
            : self::halfUp(($afterTax + $serviceAdded) * $T, 10000);

        return [$serviceIncluded + $serviceAdded, $taxIncluded + $taxAdded, $serviceAdded + $taxAdded];
    }

    /** @param  array{type: string, value: int}|null  $discount */
    private static function discount(int $amount, ?array $discount, string $field): int
    {
        if ($discount === null) {
            return 0;
        }

        return match ($discount['type']) {
            'percent' => $discount['value'] >= 0 && $discount['value'] <= 10000
                ? intdiv($amount * $discount['value'], 10000)
                : throw new InvalidArgumentException("{$field}: persen harus 0–100%."),
            'amount' => $discount['value'] >= 0 && $discount['value'] <= $amount
                ? $discount['value']
                : throw new InvalidArgumentException("{$field}: diskon melebihi harga."),
            default => throw new InvalidArgumentException("{$field}: jenis diskon tidak dikenal."),
        };
    }

    /** Pembagian dengan pembulatan setengah ke atas, khusus bilangan non-negatif. */
    private static function halfUp(int $numerator, int $denominator): int
    {
        return intdiv(2 * $numerator + $denominator, 2 * $denominator);
    }
}
