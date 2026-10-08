<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Order;
use App\Models\Product;
use Tests\TestCase;

/** pos:demo-sales: data contoh development lewat jalur order sungguhan. */
class DemoSalesTest extends TestCase
{
    public function test_generates_paid_orders_with_closed_daily_shifts_and_is_rerunnable(): void
    {
        $shop = $this->makeShop('BerryBrew');
        $this->tenancy()->run($shop->tenant->id, function () {
            $c = Category::create(['name' => 'Coffee']);
            Product::create(['category_id' => $c->id, 'name' => 'Americano', 'price' => 13000]);
            Product::create(['category_id' => $c->id, 'name' => 'Kopi Susu Aren', 'price' => 15000]);
        });

        $this->artisan('pos:demo-sales', ['code' => $shop->tenant->code, '--weeks' => 1])->assertSuccessful();

        [$count, $statuses, $days] = $this->tenancy()->run($shop->tenant->id, fn () => [
            Order::count(),
            Order::query()->distinct()->pluck('status')->all(),
            Order::query()->distinct()->count('business_date'),
        ]);
        $this->assertGreaterThan(100, $count);
        $this->assertSame(['paid'], $statuses);
        $this->assertGreaterThanOrEqual(7, $days);

        // Jalankan ulang: hari yang sudah terisi dilewati (tidak dobel).
        $this->artisan('pos:demo-sales', ['code' => $shop->tenant->code, '--weeks' => 1])->assertSuccessful();
        $this->assertSame($count, $this->tenancy()->run($shop->tenant->id, fn () => Order::count()));
    }
}
