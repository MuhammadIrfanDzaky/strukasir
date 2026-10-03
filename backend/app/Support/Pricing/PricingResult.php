<?php

namespace App\Support\Pricing;

final readonly class PricingResult
{
    /**
     * @param  list<int>  $lines  total bersih per baris (setelah diskon item)
     * @param  list<int>  $lineDiscounts
     */
    public function __construct(
        public array $lines,
        public array $lineDiscounts,
        public int $subtotal,
        public int $itemDiscountTotal,
        public int $orderDiscount,
        public int $serviceTotal,
        public int $taxTotal,
        public int $rounding,
        public int $grandTotal,
    ) {}

    public function discountTotal(): int
    {
        return $this->itemDiscountTotal + $this->orderDiscount;
    }

    /** @return array<string, mixed> */
    public function toArray(): array
    {
        return [
            'lines' => $this->lines,
            'subtotal' => $this->subtotal,
            'item_discount_total' => $this->itemDiscountTotal,
            'order_discount' => $this->orderDiscount,
            'discount_total' => $this->discountTotal(),
            'service_total' => $this->serviceTotal,
            'tax_total' => $this->taxTotal,
            'rounding' => $this->rounding,
            'grand_total' => $this->grandTotal,
        ];
    }
}
