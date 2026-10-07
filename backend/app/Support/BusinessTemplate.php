<?php

namespace App\Support;

use App\Enums\BusinessSector;
use App\Enums\Feature;
use App\Enums\SalesMode;
use App\Models\Category;
use Illuminate\Support\Facades\DB;

/**
 * Template awal per jenis usaha & cara berjualan, dipakai sekali saat pendaftaran mandiri.
 * Hanya menyetel titik awal (saklar fitur, kategori kosong, istilah); owner bebas mengubahnya
 * di Pengaturan → Fitur dan Kelola Menu. Tidak ada aturan tersembunyi di luar daftar ini.
 */
final readonly class BusinessTemplate
{
    /**
     * @param  array<string, bool>  $features  override fitur (di atas default paket)
     * @param  list<string>  $categories
     */
    public function __construct(
        public array $features,
        public array $categories,
    ) {}

    public static function for(BusinessSector $sector, SalesMode $mode): self
    {
        // Makan di tempat butuh nama/meja & bayar nanti; bawa pulang (mis. gerobak) cukup kasir cepat.
        $dineIn = $mode !== SalesMode::Takeaway;

        // Varian (suhu, gula, level pedas, topping) lazim di usaha makanan & minuman.
        $variants = in_array($sector, [BusinessSector::CoffeeShop, BusinessSector::Restaurant, BusinessSector::StreetFood], true);

        return new self(
            features: [
                Feature::CustomerName->value => $dineIn,
                Feature::OpenBill->value => $dineIn,
                Feature::Modifiers->value => $variants,
                Feature::Discounts->value => true,
                // Mati sampai owner mengisi persennya sendiri (PB1/service beda tiap daerah & usaha).
                Feature::TaxService->value => false,
                Feature::SplitPayment->value => true,
            ],
            categories: match ($sector) {
                BusinessSector::CoffeeShop => ['Kopi', 'Non Kopi', 'Makanan'],
                BusinessSector::Restaurant, BusinessSector::StreetFood => ['Makanan', 'Minuman'],
                BusinessSector::Bakery => ['Roti', 'Kue', 'Minuman'],
                BusinessSector::Retail => ['Umum'],
                BusinessSector::Service => ['Layanan'],
                BusinessSector::Other => ['Umum'],
            },
        );
    }

    /**
     * Terapkan ke kedai yang sedang aktif (dalam konteks tenant): override fitur yang berbeda dari
     * default paket — tidak pernah menyalakan fitur di luar paket — dan kategori awal yang kosong.
     */
    public function apply(string $tenantId, string $planId): void
    {
        $inPlan = DB::table('plan_features')->where('plan_id', $planId)->pluck('feature_key')->all();
        $now = now();

        $rows = [];
        foreach ($this->features as $key => $enabled) {
            // Paket menyalakan semua fiturnya; template hanya perlu mematikan (tak pernah menambah).
            if (! $enabled && in_array($key, $inPlan, true)) {
                $rows[] = ['tenant_id' => $tenantId, 'feature_key' => $key, 'enabled' => $enabled, 'created_at' => $now, 'updated_at' => $now];
            }
        }
        if ($rows !== []) {
            DB::table('tenant_features')->insert($rows);
        }

        foreach ($this->categories as $i => $name) {
            (new Category(['name' => $name, 'sort' => $i + 1]))->save();
        }
    }

    /** Label kolom nama di kasir: "meja" hanya relevan bila ada makan di tempat. */
    public static function customerLabelHint(?SalesMode $mode): string
    {
        return $mode === SalesMode::Takeaway ? 'Nama pelanggan' : 'Nama pelanggan / meja';
    }
}
