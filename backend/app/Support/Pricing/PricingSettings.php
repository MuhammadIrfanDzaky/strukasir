<?php

namespace App\Support\Pricing;

use App\Models\TenantSetting;

final readonly class PricingSettings
{
    public function __construct(
        public int $serviceBp = 0,
        public int $taxBp = 0,
        public int $roundingUnit = 0,
        // Harga di menu sudah termasuk service / pajak (dihitung mundur), diatur terpisah per kedai.
        public bool $serviceInclusive = false,
        public bool $taxInclusive = false,
    ) {}

    /** Service/pajak hanya berlaku bila fitur tax_service aktif DAN dinyalakan di pengaturan kedai. */
    public static function fromTenant(TenantSetting $s, bool $taxServiceFeature): self
    {
        return new self(
            serviceBp: $taxServiceFeature && $s->service_enabled ? $s->service_rate_bp : 0,
            taxBp: $taxServiceFeature && $s->tax_enabled ? $s->tax_rate_bp : 0,
            roundingUnit: $s->rounding_unit,
            serviceInclusive: (bool) $s->service_inclusive,
            taxInclusive: (bool) $s->tax_inclusive,
        );
    }
}
