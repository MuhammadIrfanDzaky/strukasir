<?php

namespace App\Console\Commands;

use App\Models\Customer;
use App\Models\Order;
use App\Models\Tenant;
use App\Services\CustomerService;
use App\Support\Tenancy\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * DEVELOPMENT SAJA: pelanggan contoh yang ditautkan ke sebagian order lunas yang sudah ada
 * (jalankan setelah pos:demo-sales), supaya daftar member, kelompok & dashboard bisa dicoba.
 * Ada yang setia (sering datang), yang baru, dan yang menghilang.
 *
 *   php artisan pos:demo-customers berrybrew --count=40
 */
class DemoCustomers extends Command
{
    protected $signature = 'pos:demo-customers {code=berrybrew : Kode kedai} {--count=40 : Jumlah pelanggan} {--seed=7 : Seed acak}';

    protected $description = 'Isi pelanggan contoh & tautkan ke order (development)';

    private const FIRST = ['Andi', 'Budi', 'Citra', 'Dewi', 'Eka', 'Fajar', 'Gita', 'Hendra', 'Indah', 'Joko', 'Kiki', 'Lina',
        'Mira', 'Nanda', 'Oki', 'Putri', 'Rizky', 'Sari', 'Tono', 'Wahyu', 'Yuni', 'Rina', 'Agus', 'Bayu', 'Dimas', 'Fitri'];

    private const LAST = ['Saputra', 'Lestari', 'Pratama', 'Sitorus', 'Nasution', 'Harahap', 'Siregar', 'Wijaya', 'Ginting', 'Lubis'];

    private const NOTES = ['Suka less sugar', 'Es dipisah', 'Alergi susu sapi, ganti oat milk', 'Langganan pagi', 'Selalu Kopi Susu Aren'];

    public function handle(TenantContext $context, CustomerService $customers): int
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
        $count = max(1, (int) $this->option('count'));

        [$made, $linked] = $context->run($tenant->id, function () use ($customers, $count) {
            if (Customer::query()->exists()) {
                $this->warn('Kedai ini sudah punya pelanggan; dilewati.');

                return [0, 0];
            }
            $orders = Order::query()->where('status', 'paid')->whereNull('customer_id')->orderBy('paid_at')->get(['id', 'paid_at', 'customer_label']);
            if ($orders->isEmpty()) {
                $this->warn('Belum ada order lunas. Jalankan pos:demo-sales dulu.');

                return [0, 0];
            }
            $first = CarbonImmutable::parse($orders->first()->paid_at);
            $last = CarbonImmutable::parse($orders->last()->paid_at);
            $span = max(1, $first->diffInDays($last));

            $linked = 0;
            DB::transaction(function () use ($customers, $count, $orders, $first, $span, &$linked) {
                $pool = $orders->all();
                for ($i = 0; $i < $count; $i++) {
                    $name = self::FIRST[$i % count(self::FIRST)].' '.self::LAST[mt_rand(0, count(self::LAST) - 1)];
                    $customer = $customers->create([
                        'name' => $name,
                        'phone' => '0812'.str_pad((string) (60000000 + $i * 7919), 8, '0', STR_PAD_LEFT),
                        'birth_date' => mt_rand(1, 3) === 1 ? sprintf('%d-%02d-%02d', mt_rand(1975, 2005), mt_rand(1, 12), mt_rand(1, 28)) : null,
                        'note' => mt_rand(1, 5) === 1 ? self::NOTES[mt_rand(0, count(self::NOTES) - 1)] : null,
                    ]);

                    // Pola: 25% setia (banyak kunjungan sampai akhir), 25% menghilang (hanya di awal),
                    // 20% baru (hanya minggu terakhir), sisanya acak sedang.
                    $kind = mt_rand(1, 100);
                    [$from, $to, $visits] = match (true) {
                        $kind <= 25 => [0.0, 1.0, mt_rand(8, 16)],
                        $kind <= 50 => [0.0, 0.35, mt_rand(2, 6)],
                        $kind <= 70 => [0.8, 1.0, mt_rand(1, 3)],
                        default => [0.2, 1.0, mt_rand(2, 6)],
                    };
                    $start = $first->addDays((int) floor($span * $from));
                    $end = $first->addDays((int) ceil($span * $to))->endOfDay();
                    $candidates = array_keys(array_filter($pool, fn ($o) => $o->paid_at >= $start && $o->paid_at <= $end));
                    shuffle($candidates);
                    $chosen = array_slice($candidates, 0, $visits);
                    if ($chosen === []) {
                        continue;
                    }
                    $ids = array_map(fn ($k) => $pool[$k]->id, $chosen);
                    foreach ($chosen as $k) {
                        unset($pool[$k]);
                    }
                    Order::query()->whereIn('id', $ids)->update(['customer_id' => $customer->id, 'customer_label' => $name]);
                    // Terdaftar pada kunjungan pertamanya.
                    $firstVisit = Order::query()->whereIn('id', $ids)->min('paid_at');
                    Customer::query()->whereKey($customer->id)->update(['created_at' => $firstVisit, 'updated_at' => $firstVisit]);
                    $linked += count($ids);
                }
            });

            return [$count, $linked];
        });

        $this->info("{$made} pelanggan contoh dibuat, {$linked} order ditautkan ({$tenant->name}).");

        return self::SUCCESS;
    }
}
