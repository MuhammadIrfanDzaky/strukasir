<?php

namespace App\Console\Commands;

use App\Models\Category;
use App\Models\LoyaltyEntry;
use App\Models\LoyaltyProgram;
use App\Models\LoyaltyReward;
use App\Models\Order;
use App\Models\Product;
use App\Models\Tenant;
use App\Models\User;
use App\Services\LoyaltyService;
use App\Support\Tenancy\TenantContext;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * DEVELOPMENT SAJA: program loyalitas contoh (stempel per minuman, hadiah gratis kopi & potongan)
 * dan stempel dari order member yang sudah ada (jalankan setelah pos:demo-customers).
 *
 *   php artisan pos:demo-loyalty berrybrew
 */
class DemoLoyalty extends Command
{
    protected $signature = 'pos:demo-loyalty {code=berrybrew : Kode kedai}';

    protected $description = 'Isi program loyalitas & stempel contoh (development)';

    public function handle(TenantContext $context, LoyaltyService $loyalty): int
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

        $made = $context->run($tenant->id, function () use ($loyalty) {
            if (LoyaltyProgram::query()->exists()) {
                $this->warn('Kedai ini sudah punya program loyalitas; dilewati.');

                return 0;
            }
            // Minuman = semua kategori selain makanan ringan.
            $drinks = Category::query()->whereNotIn('name', ['Snacks', 'Makanan'])->pluck('id')->all();
            $free = Product::query()->whereIn('category_id', $drinks)->where('active', true)->orderByDesc('favorite')->orderBy('price')->first();
            $owner = User::query()->where('role', 'owner')->firstOrFail();

            return DB::transaction(function () use ($loyalty, $drinks, $free, $owner) {
                $program = new LoyaltyProgram([
                    'active' => true, 'name' => 'BerryCard', 'earn_mode' => 'per_item', 'category_ids' => $drinks, 'expiry_months' => 6,
                ]);
                $program->save();
                $rewards = [['Potongan Rp 5.000', 5, 'amount', null, 5000]];
                if ($free !== null) {
                    $rewards[] = ["Gratis {$free->name}", 10, 'free_product', $free->id, 0];
                }
                $rewards[] = ['Diskon 25%', 20, 'percent', null, 2500];
                foreach ($rewards as $i => [$name, $cost, $type, $productId, $value]) {
                    LoyaltyReward::create(['name' => $name, 'cost' => $cost, 'type' => $type, 'product_id' => $productId, 'value' => $value, 'sort' => $i]);
                }

                // Stempel dari order member lama, tercatat pada waktu bayarnya.
                $made = 0;
                foreach (Order::query()->where('status', 'paid')->whereNotNull('customer_id')->orderBy('paid_at')->get() as $order) {
                    $units = $loyalty->earnFor($order, $program);
                    if ($units > 0) {
                        LoyaltyEntry::create([
                            'customer_id' => $order->customer_id, 'order_id' => $order->id, 'kind' => 'earn', 'units' => $units,
                            'user_id' => $order->cashier_id ?? $owner->id, 'created_at' => $order->paid_at,
                        ]);
                        $made += $units;
                    }
                }

                return $made;
            });
        });

        $this->info("Program BerryCard dibuat, {$made} stempel dari order member ({$tenant->name}).");

        return self::SUCCESS;
    }
}
