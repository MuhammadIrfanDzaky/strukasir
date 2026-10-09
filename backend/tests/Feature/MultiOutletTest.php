<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Ingredient;
use App\Models\Product;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class MultiOutletTest extends TestCase
{
    private object $shop;

    private string $owner;

    private string $cashier;

    private Product $latte;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->cashier = $this->pinLogin($this->shop);
        $this->latte = $this->tenancy()->run($this->shop->tenant->id, fn () => Product::create([
            'category_id' => Category::create(['name' => 'Kopi'])->id, 'name' => 'Latte', 'price' => 20000,
        ]));
    }

    private function outlet(string $name, array $extra = [])
    {
        return $this->api('POST', '/api/v1/outlets', $this->owner, ['name' => $name, ...$extra]);
    }

    private function register(array $extra = [])
    {
        return $this->api('POST', '/api/v1/devices/register', null, [
            'email' => $this->shop->owner->email, 'password' => self::OWNER_PASSWORD, 'device_id' => (string) Str::uuid(), ...$extra,
        ]);
    }

    /** Tablet kedua di outlet [$outletId] + token kasir & owner di tablet itu. */
    private function secondTablet(string $outletId): object
    {
        $res = $this->register(['outlet_id' => $outletId])->assertCreated();
        $device = $res->json('token');
        $login = fn ($user) => $this->api('POST', '/api/v1/auth/pin', $device, ['user_id' => $user->id, 'pin' => self::PIN])->assertOk()->json('token');

        return (object) ['id' => $res->json('device.id'), 'cashier' => $login($this->shop->cashier), 'owner' => $login($this->shop->owner)];
    }

    private function sell(string $token, bool $pay = true): string
    {
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $token, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => 1, 'modifier_ids' => [], 'discount' => null]],
            'expected_total' => 20000, 'customer_label' => 'Meja 1',
        ])->assertSuccessful();
        if ($pay) {
            $this->api('POST', "/api/v1/orders/{$id}/pay", $token, [
                'payments' => [['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => 20000, 'tendered' => 20000]],
                'expected_total' => 20000,
            ])->assertOk();
        }

        return $id;
    }

    public function test_kedai_lama_punya_outlet_utama_dan_outlet_kedua_butuh_fitur(): void
    {
        $menu = $this->api('GET', '/api/v1/menu', $this->cashier)->assertOk();
        $menu->assertJsonPath('outlet.code', 'O1')->assertJsonPath('outlet.name', 'BerryBrew')->assertJsonPath('outlet_count', 1);

        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['multi_outlet' => false]])->assertOk();
        $this->outlet('BerryBrew Dago')->assertUnprocessable();
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['multi_outlet' => true]])->assertOk();
        $this->outlet('BerryBrew Dago', ['address' => 'Jl. Dago 10'])->assertCreated()->assertJsonPath('data.code', 'O2');
        $this->outlet('BerryBrew Dago')->assertUnprocessable()->assertJsonValidationErrors('name');
        $this->api('POST', '/api/v1/outlets', $this->cashier, ['name' => 'X'])->assertForbidden();

        $list = $this->api('GET', '/api/v1/outlets', $this->owner)->assertOk();
        $this->assertSame(['O1', 'O2'], array_column($list->json('data.outlets'), 'code'));
        $this->assertSame('T1', $list->json('data.outlets.0.devices.0.code'));
    }

    public function test_daftar_tablet_meminta_pilihan_outlet_bila_lebih_dari_satu(): void
    {
        $o2 = $this->outlet('BerryBrew Dago')->json('data.id');
        $ask = $this->register()->assertUnprocessable()->assertJsonValidationErrors('outlet_id');
        $this->assertSame(['BerryBrew', 'BerryBrew Dago'], array_column($ask->json('outlets'), 'name'));

        $this->register(['outlet_id' => (string) Str::uuid()])->assertUnprocessable();
        $this->register(['outlet_id' => $o2])->assertCreated()->assertJsonPath('device.outlet.name', 'BerryBrew Dago');
        // Salah password tidak membocorkan daftar outlet.
        $this->api('POST', '/api/v1/devices/register', null, ['email' => $this->shop->owner->email, 'password' => 'salah'])
            ->assertUnprocessable()->assertJsonMissingPath('outlets');
    }

    public function test_order_open_bill_dan_riwayat_per_outlet(): void
    {
        $o2 = $this->outlet('BerryBrew Dago', ['address' => 'Jl. Dago 10', 'phone' => '022-123'])->json('data.id');
        $dago = $this->secondTablet($o2);
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 0])->assertCreated();
        $this->api('POST', '/api/v1/shifts/open', $dago->cashier, ['opening_cash' => 0])->assertCreated();

        $bill = $this->sell($this->cashier, pay: false); // open bill di O1
        $paid = $this->sell($dago->cashier);
        // Struk: nama outlet + alamat outlet menggantikan header umum.
        $this->api('GET', "/api/v1/orders/{$paid}", $dago->cashier)
            ->assertJsonPath('data.receipt.outlet', 'BerryBrew Dago')->assertJsonPath('data.receipt.header', "Jl. Dago 10
Telp. 022-123");

        $this->assertSame([$bill], array_column($this->api('GET', '/api/v1/orders?status=open', $this->cashier)->json('data'), 'id'));
        $this->assertSame([], $this->api('GET', '/api/v1/orders?status=open', $dago->cashier)->json('data'));
        $this->assertCount(1, $this->api('GET', '/api/v1/orders', $dago->cashier)->json('data'));
        $this->assertCount(2, $this->api('GET', '/api/v1/orders?outlet=all', $dago->owner)->json('data'));
        $this->api('GET', '/api/v1/orders?outlet=all', $dago->cashier)->assertForbidden();

        // Open bill O1 tidak bisa dibayar / diubah dari tablet O2.
        $this->api('POST', "/api/v1/orders/{$bill}/pay", $dago->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => 20000, 'tendered' => 20000]], 'expected_total' => 20000,
        ])->assertConflict();
        $this->api('PUT', "/api/v1/orders/{$bill}", $dago->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => 2, 'modifier_ids' => [], 'discount' => null]],
            'expected_total' => 40000,
        ])->assertConflict();
    }

    public function test_laporan_semua_outlet_per_outlet_dan_tutup_shift(): void
    {
        $o2 = $this->outlet('BerryBrew Dago')->json('data.id');
        $dago = $this->secondTablet($o2);
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 0])->assertCreated();
        $this->api('POST', '/api/v1/shifts/open', $dago->cashier, ['opening_cash' => 0])->assertCreated();
        $this->sell($this->cashier);
        $this->sell($dago->cashier);
        $this->sell($dago->cashier);

        $today = now($this->shop->tenant->timezone)->toDateString();
        $all = $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)->assertOk()->json('data');
        $this->assertSame(60000, $all['sales']);
        $this->assertSame([['BerryBrew', 1, 20000], ['BerryBrew Dago', 2, 40000]],
            array_map(fn ($r) => [$r['name'], $r['orders'], $r['sales']], $all['by_outlet']));

        $one = $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}&outlet={$o2}", $this->owner)->assertOk()->json('data');
        $this->assertSame([40000, 2, null], [$one['sales'], $one['orders'], $one['by_outlet']]);
        $this->assertSame(40000, $one['by_method']['cash']);

        // CSV: kolom Outlet; `outlet` membatasi ke satu outlet.
        $csv = function (?string $outlet) use ($today) {
            $url = $this->api('POST', '/api/v1/reports/export-link', $this->owner, ['type' => 'tax', 'from' => $today, 'to' => $today, 'outlet' => $outlet])
                ->assertOk()->json('data.url');
            $this->app['auth']->forgetGuards();
            $this->tenancy()->clear();

            return $this->get($url)->assertOk()->streamedContent();
        };
        $this->assertStringContainsString("{$today};BerryBrew;1;20000", $csv('all'));
        $this->assertStringContainsString("{$today};\"BerryBrew Dago\";2;40000", $csv('all'));
        $this->assertStringNotContainsString(';BerryBrew;', $csv($o2));

        $shift = $this->api('GET', '/api/v1/shifts/current', $dago->cashier)->json('data.id');
        $text = $this->api('GET', "/api/v1/shifts/{$shift}/report", $dago->cashier)->json('data.text');
        $this->assertStringContainsString('*Laporan shift BerryBrew* · BerryBrew Dago', $text);
        $this->assertStringContainsString('Total hari ini BerryBrew Dago: Rp40.000 · 2 transaksi', $text);
        $this->assertStringContainsString('Total hari ini (semua outlet): Rp60.000 · 3 transaksi', $text);
    }

    public function test_stok_terpisah_per_outlet(): void
    {
        $o2 = $this->outlet('BerryBrew Dago')->json('data.id');
        $dago = $this->secondTablet($o2);
        $susu = $this->api('POST', '/api/v1/ingredients', $this->owner, ['name' => 'Susu', 'unit' => 'ml'])->json('data.id');
        $this->api('PUT', "/api/v1/recipes/product/{$this->latte->id}", $this->owner, ['items' => [['ingredient_id' => $susu, 'qty' => 150]]])->assertOk();
        // Pembelian dicatat owner dari tablet O1 untuk O1 (default) dan untuk O2 (pilih outlet).
        $this->api('POST', '/api/v1/stock/purchases', $this->owner, ['id' => (string) Str::uuid(),
            'lines' => [['ingredient_id' => $susu, 'qty' => 1000, 'total_cost' => 20000]]])->assertCreated();
        $this->api('POST', '/api/v1/stock/purchases', $this->owner, ['id' => (string) Str::uuid(), 'outlet_id' => $o2,
            'lines' => [['ingredient_id' => $susu, 'qty' => 1000, 'total_cost' => 30000]]])->assertCreated();
        $this->api('POST', '/api/v1/stock/purchases', $this->owner, ['id' => (string) Str::uuid(), 'outlet_id' => $o2, 'paid_from_cash' => true,
            'lines' => [['ingredient_id' => $susu, 'qty' => 1, 'total_cost' => 1]]])->assertUnprocessable()->assertJsonValidationErrors('paid_from_cash');

        $this->api('POST', '/api/v1/shifts/open', $dago->cashier, ['opening_cash' => 0])->assertCreated();
        $order = $this->sell($dago->cashier);

        $stock = fn (string $outlet) => $this->tenancy()->run($this->shop->tenant->id,
            fn () => Ingredient::query()->withStock($outlet)->findOrFail($susu)->only(['stock', 'avg_cost']));
        $this->assertEquals(['stock' => 1000, 'avg_cost' => 20], $stock($this->shop->device->outlet_id));
        $this->assertEquals(['stock' => 850, 'avg_cost' => 30], $stock($o2));
        // HPP order O2 dari modal O2.
        $this->assertSame(4500, $this->tenancy()->run($this->shop->tenant->id, fn () => (int) DB::table('order_items')->where('order_id', $order)->value('unit_cost')));

        $this->assertSame(1000.0, (float) $this->api('GET', '/api/v1/inventory', $this->owner)->json('data.ingredients.0.stock'));
        $this->assertSame(850.0, (float) $this->api('GET', "/api/v1/inventory?outlet={$o2}", $this->owner)->json('data.ingredients.0.stock'));
        $this->assertSame(850.0, (float) $this->api('GET', '/api/v1/inventory', $dago->owner)->json('data.ingredients.0.stock'));
        $this->assertSame(['sale', 'purchase'], array_column(
            $this->api('GET', "/api/v1/ingredients/{$susu}/movements?outlet={$o2}", $this->owner)->json('data.movements'), 'kind'));
    }

    public function test_pindah_tablet_dan_nonaktifkan_outlet(): void
    {
        $o2 = $this->outlet('BerryBrew Dago')->json('data.id');
        $o1 = $this->shop->device->outlet_id;
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 0])->assertCreated();
        $this->api('PUT', "/api/v1/devices/{$this->shop->device->id}/outlet", $this->owner, ['outlet_id' => $o2])->assertConflict();
        $this->api('PUT', "/api/v1/outlets/{$o1}", $this->owner, ['name' => 'BerryBrew', 'active' => false])
            ->assertUnprocessable()->assertJsonValidationErrors('active'); // masih ada tablet

        $this->api('POST', '/api/v1/shifts/close', $this->cashier, ['counted_cash' => 0])->assertOk();
        $this->api('PUT', "/api/v1/devices/{$this->shop->device->id}/outlet", $this->owner, ['outlet_id' => $o2])->assertOk();
        $this->api('GET', '/api/v1/menu', $this->cashier)->assertJsonPath('outlet.name', 'BerryBrew Dago');

        $this->api('PUT', "/api/v1/outlets/{$o1}", $this->owner, ['name' => 'BerryBrew Lama', 'active' => false])->assertOk();
        $this->api('PUT', "/api/v1/outlets/{$o2}", $this->owner, ['name' => 'BerryBrew Dago', 'active' => false])
            ->assertUnprocessable()->assertJsonValidationErrors('active'); // outlet aktif terakhir
    }
}
