<?php

namespace App\Support;

use App\Enums\Feature;
use App\Models\Plan;
use Illuminate\Support\Facades\DB;

/**
 * Daftar paket langganan (satu sumber untuk migrasi, seeder, dan tes). Harga per usaha (bukan per outlet).
 * `standard` = paket internal lama (BerryBrew & usaha awal): semua fitur, tanpa batas, tidak ditawarkan.
 */
final class PlanCatalog
{
    /** Masa coba paket gratis & batas waktu bayar paket berbayar yang dipilih saat daftar. */
    public const TRIAL_DAYS = 7;

    public const FREE = 'gratis';

    /** Paket yang disorot di app ("Paling banyak dipilih"). */
    public const RECOMMENDED = 'tumbuh';

    /** Periode bayar: [jumlah bulan, diskon %]. */
    public const PERIODS = [
        'month' => [1, 0],
        'quarter' => [3, 10],
        'half' => [6, 15],
        'year' => [12, 20],
    ];

    public static function months(string $period): int
    {
        return self::PERIODS[$period][0];
    }

    /** Harga satu periode: harga bulanan × bulan − diskon periode, dibulatkan ke ratusan. */
    public static function price(int $priceMonth, string $period): int
    {
        [$months, $discount] = self::PERIODS[$period];

        return (int) round($priceMonth * $months * (100 - $discount) / 100, -2);
    }

    /** @return array<string, array<string, mixed>> */
    public static function plans(): array
    {
        $basic = [
            Feature::CustomerName, Feature::OpenBill, Feature::Modifiers, Feature::Discounts,
            Feature::TaxService, Feature::SplitPayment, Feature::Reports, Feature::Customers,
        ];
        $all = Feature::cases();

        return [
            self::FREE => [
                'name' => 'Gratis', 'tagline' => 'Coba semua fitur kasir dasar selama 7 hari.',
                'price_month' => 0, 'max_outlets' => 1, 'max_devices' => 1, 'max_staff' => 2,
                'sort' => 1, 'public' => true, 'features' => $basic,
            ],
            'mulai' => [
                'name' => 'Mulai', 'tagline' => 'Untuk usaha kecil & gerobak: kasir lengkap, laporan, promo.',
                'price_month' => 9900, 'max_outlets' => 1, 'max_devices' => 2, 'max_staff' => 5,
                'sort' => 2, 'public' => true, 'features' => [...$basic, Feature::Promotions],
            ],
            'tumbuh' => [
                'name' => 'Tumbuh', 'tagline' => 'Member & loyalitas, stok & resep, sampai 3 outlet.',
                'price_month' => 24900, 'max_outlets' => 3, 'max_devices' => 9, 'max_staff' => 15,
                'sort' => 3, 'public' => true, 'features' => $all,
            ],
            'juragan' => [
                'name' => 'Juragan', 'tagline' => 'Sampai 10 outlet, tablet & pegawai tanpa batas, bantuan prioritas.',
                'price_month' => 49900, 'max_outlets' => 10, 'max_devices' => null, 'max_staff' => null,
                'sort' => 4, 'public' => true, 'features' => $all,
            ],
            'standard' => [
                'name' => 'Standard', 'tagline' => null,
                'price_month' => 0, 'max_outlets' => null, 'max_devices' => null, 'max_staff' => null,
                'sort' => 99, 'public' => false, 'features' => $all,
            ],
        ];
    }

    /**
     * Fitur yang tidak ada di paket ini + paket publik termurah yang membukanya, untuk ditampilkan
     * terkunci di aplikasi ("Buka di paket Tumbuh"). Paket tak dikenal → tidak ada yang terkunci.
     *
     * @return list<array{key: string, label: string, description: string, plan: array{code: string, name: string}}>
     */
    public static function lockedFeatures(?string $planCode): array
    {
        $plans = self::plans();
        if ($planCode === null || ! isset($plans[$planCode])) {
            return [];
        }
        $has = $plans[$planCode]['features'];
        $public = array_filter($plans, fn ($p) => $p['public']);
        uasort($public, fn ($a, $b) => $a['sort'] <=> $b['sort']);
        $locked = [];
        foreach (Feature::cases() as $f) {
            if (in_array($f, $has, true)) {
                continue;
            }
            foreach ($public as $code => $p) {
                if ($p['sort'] > $plans[$planCode]['sort'] && in_array($f, $p['features'], true)) {
                    $locked[] = ['key' => $f->value, 'label' => $f->label(), 'description' => $f->description(),
                        'plan' => ['code' => $code, 'name' => $p['name']]];
                    break;
                }
            }
        }

        return $locked;
    }

    /** Buat/perbarui paket & fitur tiap paket (idempotent). */
    public static function sync(): void
    {
        foreach (Feature::cases() as $feature) {
            DB::table('features')->updateOrInsert(
                ['key' => $feature->value],
                ['description' => $feature->description(), 'updated_at' => now(), 'created_at' => now()],
            );
        }

        foreach (self::plans() as $code => $def) {
            $features = array_map(fn (Feature $f) => $f->value, $def['features']);
            unset($def['features']);
            $def['price_year'] = self::price($def['price_month'], 'year');
            $plan = Plan::query()->firstOrNew(['code' => $code]);
            $plan->forceFill($def)->save();

            DB::table('plan_features')->where('plan_id', $plan->id)->whereNotIn('feature_key', $features)->delete();
            foreach ($features as $key) {
                DB::table('plan_features')->insertOrIgnore(['plan_id' => $plan->id, 'feature_key' => $key]);
            }
        }
    }
}
