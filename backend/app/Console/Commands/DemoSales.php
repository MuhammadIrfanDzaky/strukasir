<?php

namespace App\Console\Commands;

use App\Enums\Role;
use App\Models\Device;
use App\Models\Order;
use App\Models\Product;
use App\Models\Shift;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use App\Services\OrderService;
use App\Services\ShiftService;
use App\Support\Pricing\PricingService;
use App\Support\Pricing\PricingSettings;
use App\Support\Tenancy\FeatureGate;
use App\Support\Tenancy\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Console\Command;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

/**
 * DEVELOPMENT SAJA: isi riwayat penjualan contoh beberapa minggu supaya dashboard bisa dicoba.
 * Order dibuat lewat OrderService (harga, pajak, nomor order, shift) seperti transaksi sungguhan,
 * dengan pola realistis kedai kopi: ramai pagi & sore–malam, akhir pekan lebih ramai, Cold lebih laku.
 *
 *   php artisan pos:demo-sales berrybrew --weeks=4
 */
class DemoSales extends Command
{
    protected $signature = 'pos:demo-sales {code=berrybrew : Kode kedai} {--weeks=4 : Jumlah minggu ke belakang} {--seed=42 : Seed acak (hasil sama tiap kali)}';

    protected $description = 'Isi penjualan contoh untuk dashboard (development)';

    /** Bobot kepopuleran per nama produk (lainnya 1). */
    private const POPULAR = [
        'Kopi Susu Aren' => 9, 'Americano' => 7, 'Sanger' => 5, 'Cafe Latte' => 5, 'Berrycano' => 4,
        'Hazelnut Latte' => 3, 'Matcha Latte' => 4, 'Thai Tea' => 3, 'Lemon Tea' => 3, 'Cappuccino' => 3,
        'Kentang Goreng' => 3, 'Tortilla' => 2, 'Air Mineral' => 3, 'Roti' => 2, 'Peyek' => 2,
    ];

    /** Rata-rata order per jam (hari kerja). */
    private const HOURS = [
        8 => 2, 9 => 3, 10 => 5, 11 => 4, 12 => 3, 13 => 3, 14 => 3, 15 => 4, 16 => 5,
        17 => 6, 18 => 5, 19 => 7, 20 => 6, 21 => 4, 22 => 2,
    ];

    private const NAMES = ['Andi', 'Budi', 'Citra', 'Dewi', 'Eka', 'Fajar', 'Gita', 'Hendra', 'Indah', 'Joko', 'Kiki',
        'Lina', 'Mira', 'Nanda', 'Oki', 'Putri', 'Rizky', 'Sari', 'Tono', 'Wahyu', 'Yuni'];

    public function handle(TenantContext $context, OrderService $orders, ShiftService $shifts, PricingService $pricing, FeatureGate $features): int
    {
        if (app()->isProduction()) {
            $this->error('Perintah ini hanya untuk development.');

            return self::FAILURE;
        }
        $tenant = Tenant::where('code', $this->argument('code'))->first();
        if ($tenant === null) {
            $this->error('Kedai tidak ditemukan.');

            return self::FAILURE;
        }

        mt_srand((int) $this->option('seed'));
        $weeks = max(1, (int) $this->option('weeks'));

        $count = $context->run($tenant->id, function () use ($tenant, $orders, $shifts, $pricing, $features, $weeks) {
            $device = Device::query()->whereNull('revoked_at')->orderBy('code')->first()
                ?? tap(new Device(['name' => 'Tablet Demo']), function (Device $d) {
                    $d->code = 'T'.(Device::query()->count() + 1);
                    $d->save();
                });
            $staff = User::query()->where('active', true)->get();
            $cashiers = $staff->where('role', Role::Cashier)->values();
            $owner = $staff->firstWhere('role', Role::Owner);
            if ($cashiers->isEmpty()) {
                $cashiers = collect([$owner]);
            }

            $products = Product::query()->where('active', true)->where('sold_out', false)->with('modifierGroups.modifiers')->get();
            // Modal contoh ±40% harga bila belum diisi, supaya laba kotor terlihat.
            foreach ($products as $p) {
                if ($p->cost === null) {
                    $p->forceFill(['cost' => (int) (round($p->price * 0.4 / 500) * 500)])->save();
                }
            }
            $weighted = $products->flatMap(fn (Product $p) => array_fill(0, self::POPULAR[$p->name] ?? 1, $p))->values();
            $settings = PricingSettings::fromTenant(TenantSetting::query()->firstOrFail(), $features->enabled('tax_service'));
            $askName = $features->enabled('customer_name');

            $tz = $tenant->timezone;
            // Waktu nyata diambil sekali: di dalam loop "sekarang" digeser ke jam tiap order.
            $realNow = CarbonImmutable::now($tz);
            $today = $realNow->startOfDay();
            $made = 0;

            for ($day = $today->subDays($weeks * 7); $day->lte($today); $day = $day->addDay()) {
                // Hari yang sudah punya penjualan dilewati (aman dijalankan ulang, tidak dobel).
                if (Order::query()->where('business_date', $day->toDateString())->exists()) {
                    continue;
                }
                $cashier = $cashiers[mt_rand(0, $cashiers->count() - 1)];
                $weekend = $day->isWeekend();
                $times = [];
                foreach (self::HOURS as $hour => $avg) {
                    $n = max(0, (int) round($avg * ($weekend ? 1.35 : 1) * (mt_rand(70, 130) / 100)));
                    for ($i = 0; $i < $n; $i++) {
                        $times[] = $day->setTime($hour, mt_rand(0, 59), mt_rand(0, 59));
                    }
                }
                sort($times);
                $times = array_values(array_filter($times, fn ($t) => $t->lt($realNow)));
                if ($times === []) {
                    continue;
                }

                Carbon::setTestNow($day->setTime(7, 45)->utc());
                $shift = $shifts->current($device) ?? $shifts->open($device, $cashier, 200000);

                foreach ($times as $at) {
                    Carbon::setTestNow($at->utc());
                    $items = [];
                    $lines = [];
                    foreach (range(1, $this->lineCount()) as $_) {
                        $product = $weighted[mt_rand(0, $weighted->count() - 1)];
                        $mods = $this->pickModifiers($product);
                        $qty = mt_rand(1, 10) <= 8 ? 1 : 2;
                        $items[] = ['id' => (string) Str::uuid(), 'product_id' => $product->id, 'qty' => $qty,
                            'modifier_ids' => array_column($mods, 'id'), 'note' => null, 'discount' => null];
                        $lines[] = ['unit_price' => $product->price + array_sum(array_column($mods, 'price_delta')), 'qty' => $qty];
                    }
                    $total = $pricing->calculate($lines, null, $settings)->grandTotal;
                    $label = $askName ? (mt_rand(1, 3) === 1 ? 'Meja '.mt_rand(1, 12) : self::NAMES[mt_rand(0, count(self::NAMES) - 1)]) : null;

                    $id = (string) Str::uuid();
                    $orders->upsert($id, ['items' => $items, 'customer_label' => $label, 'expected_total' => $total],
                        $cashier, $device, $tenant);

                    Carbon::setTestNow($at->addMinutes(mt_rand(1, 4))->utc());
                    $method = $this->method();
                    $tendered = $method === 'cash' ? $this->cashTendered($total) : null;
                    $orders->pay($id, [[
                        'id' => (string) Str::uuid(), 'method' => $method, 'amount' => $total, 'tendered' => $tendered,
                    ]], $total, $cashier, $device);
                    $made++;
                }

                // Tutup shift di akhir hari (kecuali hari ini, biarkan terbuka seperti kedai yang masih buka).
                if (! $day->equalTo($today)) {
                    Carbon::setTestNow($day->setTime(23, 15)->utc());
                    $expected = $shifts->summary(Shift::query()->findOrFail($shift->id))['expected_cash'];
                    $shifts->close($shift, $cashier, $expected + (mt_rand(1, 6) === 1 ? -mt_rand(1, 5) * 1000 : 0), null);
                }
            }

            Carbon::setTestNow();

            return $made;
        });

        $this->info("{$count} transaksi contoh dibuat untuk {$tenant->name} ({$weeks} minggu).");

        return self::SUCCESS;
    }

    private function lineCount(): int
    {
        $r = mt_rand(1, 100);

        return $r <= 55 ? 1 : ($r <= 85 ? 2 : 3);
    }

    /** @return list<array{id: string, price_delta: int}> */
    private function pickModifiers(Product $product): array
    {
        $chosen = [];
        foreach ($product->modifierGroups as $group) {
            $options = $group->modifiers->where('active', true)->values();
            if ($options->isEmpty()) {
                continue;
            }
            if (str_starts_with($group->name, 'Suhu')) {
                $m = $options->firstWhere('name', mt_rand(1, 100) <= 65 ? 'Cold' : 'Hot') ?? $options->first();
                $chosen[] = ['id' => $m->id, 'price_delta' => $m->price_delta];
            } elseif ($group->allow_quantity) {
                if (mt_rand(1, 100) <= 15) {
                    $m = $options->first();
                    foreach (range(1, mt_rand(1, 10) <= 8 ? 1 : 2) as $_) {
                        $chosen[] = ['id' => $m->id, 'price_delta' => $m->price_delta];
                    }
                }
            } elseif ($group->min_select > 0 || mt_rand(1, 100) <= 25) {
                $m = $options[mt_rand(0, $options->count() - 1)];
                $chosen[] = ['id' => $m->id, 'price_delta' => $m->price_delta];
            }
        }

        return $chosen;
    }

    private function method(): string
    {
        $r = mt_rand(1, 100);

        return $r <= 55 ? 'cash' : ($r <= 90 ? 'qris' : 'debit');
    }

    /** Uang tunai yang umum diterima: pas, atau dibulatkan ke pecahan 5rb/10rb/20rb/50rb/100rb. */
    private function cashTendered(int $total): int
    {
        $options = [$total];
        foreach ([5000, 10000, 20000, 50000, 100000] as $note) {
            $options[] = (int) (ceil($total / $note) * $note);
        }

        return $options[mt_rand(0, count($options) - 1)];
    }
}
