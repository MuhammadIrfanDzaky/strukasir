<?php

namespace App\Support;

use App\Enums\BusinessGroup;
use App\Enums\BusinessSector;
use App\Enums\Feature;
use App\Enums\SalesMode;
use App\Models\Category;
use App\Models\TenantSetting;
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
        // Pilihan Takeaway | Dine-in di kasir & jenis awalnya (bisa diubah di Pengaturan → Fitur).
        public bool $orderTypes = false,
        public string $defaultOrderType = 'takeaway',
    ) {}

    public static function for(BusinessSector $sector, ?SalesMode $mode): self
    {
        // Nama pelanggan & bayar nanti: makan di tempat, jasa (bayar saat ambil: laundry, bengkel),
        // dan salon (bayar setelah layanan). Toko & apotek cukup kasir cepat.
        [$customerName, $openBill] = match ($sector->group()) {
            BusinessGroup::Food => [$mode !== SalesMode::Takeaway, $mode !== SalesMode::Takeaway],
            BusinessGroup::Service, BusinessGroup::Beauty => [true, true],
            BusinessGroup::Other => [true, false],
            BusinessGroup::Retail, BusinessGroup::Health => [false, false],
        };

        // Varian (suhu, gula, level pedas, topping) lazim di makanan & minuman siap saji.
        $variants = in_array($sector, [
            BusinessSector::CoffeeShop, BusinessSector::Restaurant, BusinessSector::StreetFood, BusinessSector::Beverage,
        ], true);

        return new self(
            features: [
                Feature::CustomerName->value => $customerName,
                Feature::OpenBill->value => $openBill,
                Feature::Modifiers->value => $variants,
                Feature::Discounts->value => true,
                // Mati sampai owner mengisi persennya sendiri (PB1/service beda tiap daerah & usaha).
                Feature::TaxService->value => false,
                Feature::SplitPayment->value => true,
            ],
            categories: self::categories($sector),
            orderTypes: $sector->servesDineIn() && $mode !== SalesMode::Takeaway,
            defaultOrderType: $sector === BusinessSector::Restaurant || $mode === SalesMode::DineIn ? 'dine_in' : 'takeaway',
        );
    }

    /** @return list<string> kategori awal (kosong, tanpa produk contoh) */
    private static function categories(BusinessSector $sector): array
    {
        return match ($sector) {
            BusinessSector::CoffeeShop => ['Kopi', 'Non Kopi', 'Makanan'],
            BusinessSector::Restaurant, BusinessSector::StreetFood => ['Makanan', 'Minuman'],
            BusinessSector::Catering => ['Paket', 'Menu Satuan'],
            BusinessSector::Bakery => ['Roti', 'Kue', 'Minuman'],
            BusinessSector::Beverage => ['Minuman', 'Topping'],
            BusinessSector::FrozenFood => ['Frozen Food', 'Pangan Segar'],
            BusinessSector::Fashion => ['Pakaian', 'Aksesoris'],
            BusinessSector::Gadget => ['Pulsa & Data', 'Aksesoris', 'Gadget'],
            BusinessSector::PetShop => ['Makanan Hewan', 'Aksesoris'],
            BusinessSector::Laundry => ['Kiloan', 'Satuan'],
            BusinessSector::Workshop => ['Servis', 'Suku Cadang', 'Cuci'],
            BusinessSector::Printing => ['Fotokopi & Cetak', 'ATK'],
            BusinessSector::Pharmacy => ['Obat Bebas', 'Vitamin & Suplemen', 'Alat Kesehatan'],
            BusinessSector::Optic => ['Kacamata', 'Lensa'],
            BusinessSector::Fitness => ['Membership', 'Kelas', 'Minuman'],
            BusinessSector::Salon => ['Potong Rambut', 'Perawatan', 'Produk'],
            BusinessSector::Spa, BusinessSector::NailArt => ['Layanan', 'Produk'],
            BusinessSector::Skincare => ['Skincare', 'Makeup'],
            default => match ($sector->group()) {
                BusinessGroup::Service, BusinessGroup::Health => ['Layanan'],
                default => ['Umum'],
            },
        };
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

        TenantSetting::query()->update([
            'order_types_enabled' => $this->orderTypes,
            'default_order_type' => $this->defaultOrderType,
        ]);
    }

    /** Label kolom nama di kasir: "meja" hanya untuk usaha makanan yang melayani makan di tempat. */
    public static function customerLabelHint(?BusinessSector $sector, ?SalesMode $mode, bool $orderTypes = false): string
    {
        // Jenis pesanan aktif: meja punya kolom sendiri (Dine-in), kolom ini cukup nama.
        if ($orderTypes) {
            return 'Nama pelanggan';
        }
        // Kedai lama (tanpa profil) = kedai makan seperti BerryBrew.
        if ($sector === null) {
            return 'Nama pelanggan / meja';
        }

        return $sector->group() === BusinessGroup::Food && $mode !== SalesMode::Takeaway
            ? 'Nama pelanggan / meja'
            : 'Nama pelanggan';
    }
}
