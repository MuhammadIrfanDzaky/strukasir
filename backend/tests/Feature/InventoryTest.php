<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Ingredient;
use App\Models\Modifier;
use App\Models\ModifierGroup;
use App\Models\Product;
use App\Models\Shift;
use App\Services\ShiftService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class InventoryTest extends TestCase
{
    private object $shop;

    private string $cashier;

    private string $owner;

    private Product $latte;

    private Modifier $oat;

    private Modifier $shot;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->cashier = $this->pinLogin($this->shop);
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 200000])->assertCreated();
        $this->inShop(function () {
            $kopi = Category::create(['name' => 'Kopi']);
            $susu = ModifierGroup::create(['name' => 'Susu', 'min_select' => 0, 'max_select' => 1]);
            $this->oat = $susu->modifiers()->create(['name' => 'Oat milk', 'price_delta' => 5000]);
            $extra = ModifierGroup::create(['name' => 'Tambahan', 'min_select' => 0, 'max_select' => 3, 'allow_quantity' => true, 'max_quantity' => 3]);
            $this->shot = $extra->modifiers()->create(['name' => 'Extra shot', 'price_delta' => 4000]);
            $this->latte = Product::create(['category_id' => $kopi->id, 'name' => 'Latte', 'price' => 25000, 'cost' => 9999]);
            $this->latte->modifierGroups()->sync([
                $susu->id => ['tenant_id' => $this->shop->tenant->id, 'sort' => 0],
                $extra->id => ['tenant_id' => $this->shop->tenant->id, 'sort' => 1],
            ]);
        });
    }

    private function inShop(callable $fn): mixed
    {
        return $this->tenancy()->run($this->shop->tenant->id, $fn);
    }

    private function ingredient(string $name, string $unit, ?float $min = null): string
    {
        return $this->api('POST', '/api/v1/ingredients', $this->owner, ['name' => $name, 'unit' => $unit, 'min_stock' => $min])
            ->assertCreated()->json('data.id');
    }

    private function stock(string $id): array
    {
        return $this->inShop(fn () => Ingredient::query()->withStock($this->shop->device->outlet_id)->findOrFail($id)->only(['stock', 'avg_cost']));
    }

    private function purchase(array $lines, array $extra = [])
    {
        return $this->api('POST', '/api/v1/stock/purchases', $this->owner, ['id' => (string) Str::uuid(), 'lines' => $lines, ...$extra]);
    }

    /** Biji kopi, susu, oat, cup dengan stok & modal awal; resep latte + varian. */
    private function stocked(): array
    {
        $ids = [
            'kopi' => $this->ingredient('Biji kopi', 'g', 500),
            'susu' => $this->ingredient('Susu', 'ml', 1000),
            'oat' => $this->ingredient('Oat milk', 'ml'),
            'cup' => $this->ingredient('Cup 12oz', 'pcs', 20),
        ];
        $this->purchase([
            ['ingredient_id' => $ids['kopi'], 'qty' => 1000, 'total_cost' => 200000], // Rp200/g
            ['ingredient_id' => $ids['susu'], 'qty' => 2000, 'total_cost' => 40000], // Rp20/ml
            ['ingredient_id' => $ids['oat'], 'qty' => 1000, 'total_cost' => 50000], // Rp50/ml
            ['ingredient_id' => $ids['cup'], 'qty' => 100, 'total_cost' => 80000], // Rp800/pcs
        ])->assertCreated();
        $this->api('PUT', "/api/v1/recipes/product/{$this->latte->id}", $this->owner, ['items' => [
            ['ingredient_id' => $ids['kopi'], 'qty' => 18],
            ['ingredient_id' => $ids['susu'], 'qty' => 150],
            ['ingredient_id' => $ids['cup'], 'qty' => 1],
        ]])->assertOk()->assertJsonPath("data.product_costs.{$this->latte->id}", 3600 + 3000 + 800);
        $this->api('PUT', "/api/v1/recipes/modifier/{$this->oat->id}", $this->owner, ['items' => [
            ['ingredient_id' => $ids['oat'], 'qty' => 150],
            ['ingredient_id' => $ids['susu'], 'qty' => -150], // pengganti susu sapi
        ]])->assertOk();
        $this->api('PUT', "/api/v1/recipes/modifier/{$this->shot->id}", $this->owner, ['items' => [
            ['ingredient_id' => $ids['kopi'], 'qty' => 18],
        ]])->assertOk();

        return $ids;
    }

    private function sell(array $modifiers, int $qty, int $total): string
    {
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => $qty,
                'modifier_ids' => array_map(fn (Modifier $m) => $m->id, $modifiers), 'discount' => null]],
            'expected_total' => $total,
        ])->assertSuccessful();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'qris', 'amount' => $total, 'reference' => 'x']],
            'expected_total' => $total,
        ])->assertOk();

        return $id;
    }

    public function test_hanya_owner_dan_hanya_bila_fitur_aktif(): void
    {
        $this->api('GET', '/api/v1/inventory', $this->cashier)->assertForbidden();
        $this->api('POST', '/api/v1/ingredients', $this->cashier, ['name' => 'Susu', 'unit' => 'ml'])->assertForbidden();
        $this->api('GET', '/api/v1/inventory', $this->owner)->assertOk()->assertJsonPath('data.ingredients', []);

        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['inventory' => false]])->assertOk();
        $this->api('GET', '/api/v1/inventory', $this->owner)->assertForbidden();
    }

    public function test_bahan_unik_dan_satuan_terkunci_setelah_ada_riwayat(): void
    {
        $susu = $this->ingredient('Susu', 'ml', 1000);
        $this->api('POST', '/api/v1/ingredients', $this->owner, ['name' => ' Susu ', 'unit' => 'ml'])->assertUnprocessable()->assertJsonValidationErrors('name');
        $this->api('PUT', "/api/v1/ingredients/{$susu}", $this->owner, ['name' => 'Susu UHT', 'unit' => 'g'])->assertOk();
        $this->purchase([['ingredient_id' => $susu, 'qty' => 10, 'total_cost' => 100]])->assertCreated();
        $this->api('PUT', "/api/v1/ingredients/{$susu}", $this->owner, ['name' => 'Susu UHT', 'unit' => 'ml'])
            ->assertUnprocessable()->assertJsonValidationErrors('unit');
    }

    public function test_satuan_dasar_tambahan_diterima_dan_satuan_asing_ditolak(): void
    {
        foreach (['kg', 'L', 'butir', 'sachet', 'bungkus'] as $unit) {
            $this->api('POST', '/api/v1/ingredients', $this->owner, ['name' => "Bahan {$unit}", 'unit' => $unit])->assertCreated();
        }
        $this->api('POST', '/api/v1/ingredients', $this->owner, ['name' => 'Bahan ons', 'unit' => 'ons'])
            ->assertUnprocessable()->assertJsonValidationErrors('unit');
    }

    public function test_pembelian_modal_rata_rata_bergerak_dan_kiriman_ulang_aman(): void
    {
        $susu = $this->ingredient('Susu', 'ml');
        $id = (string) Str::uuid();
        $body = ['id' => $id, 'supplier' => 'Toko Susu', 'lines' => [['ingredient_id' => $susu, 'qty' => 1000, 'total_cost' => 18000]]];
        $this->api('POST', '/api/v1/stock/purchases', $this->owner, $body)->assertCreated()->assertJsonPath('data.replayed', false);
        $this->api('POST', '/api/v1/stock/purchases', $this->owner, $body)->assertCreated()->assertJsonPath('data.replayed', true);
        $this->assertEquals(['stock' => 1000, 'avg_cost' => 18], $this->stock($susu));

        // 1000 ml @18 + 1000 ml @22 → rata-rata 20.
        $this->purchase([['ingredient_id' => $susu, 'qty' => 1000, 'total_cost' => 22000]])->assertCreated();
        $this->assertEquals(['stock' => 2000, 'avg_cost' => 20], $this->stock($susu));

        $this->purchase([['ingredient_id' => $susu, 'qty' => 1, 'total_cost' => 1], ['ingredient_id' => $susu, 'qty' => 2, 'total_cost' => 1]])
            ->assertUnprocessable()->assertJsonValidationErrors('lines');
        $this->purchase([['ingredient_id' => $susu, 'qty' => 0, 'total_cost' => 1]])->assertUnprocessable();
    }

    public function test_pembelian_dari_laci_jadi_kas_keluar_bukan_biaya(): void
    {
        $susu = $this->ingredient('Susu', 'ml');
        $this->purchase([['ingredient_id' => $susu, 'qty' => 1000, 'total_cost' => 20000]], ['paid_from_cash' => true, 'supplier' => 'Pasar'])
            ->assertCreated();
        $moves = $this->api('GET', '/api/v1/shifts/current/cash-movements', $this->cashier)->assertOk();
        $moves->assertJsonPath('data.0.category', 'stock_purchase')->assertJsonPath('data.0.amount', 20000);
        $summary = $this->inShop(fn () => app(ShiftService::class)->summary(Shift::query()->firstOrFail()));
        $this->assertSame([20000, 180000], [$summary['cash_out'], $summary['expected_cash']]);

        $today = now($this->shop->tenant->timezone)->toDateString();
        $report = $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)->assertOk();
        $report->assertJsonPath('data.expenses.total', 0)->assertJsonPath('data.stock.purchases', 20000);

        // Kasir tidak bisa memilih kategori internal ini secara manual.
        $this->api('POST', '/api/v1/shifts/current/cash-movements', $this->cashier, [
            'id' => (string) Str::uuid(), 'kind' => 'out', 'category' => 'stock_purchase', 'amount' => 1000,
        ])->assertUnprocessable();
        $this->assertNotContains('stock_purchase', array_column(
            $moves->json('categories'), 'key'));
    }

    public function test_resep_hpp_otomatis_potong_stok_saat_lunas_dan_kembali_saat_void(): void
    {
        $ids = $this->stocked();

        // HPP terlihat owner di menu; kasir tidak.
        $menu = collect($this->api('GET', '/api/v1/menu', $this->owner)->json('products'))->firstWhere('id', $this->latte->id);
        $this->assertSame(7400, $menu['recipe_cost']);
        $this->assertArrayNotHasKey('recipe_cost', collect($this->api('GET', '/api/v1/menu', $this->cashier)->json('products'))->firstWhere('id', $this->latte->id));

        // 2 latte oat + extra shot ×2: kopi (18+36)×2, oat 300, susu 0, cup 2.
        $order = $this->sell([$this->oat, $this->shot, $this->shot], 2, 2 * (25000 + 5000 + 8000));
        $unitCost = $this->inShop(fn () => DB::table('order_items')->where('order_id', $order)->value('unit_cost'));
        $this->assertSame(7400 + (150 * 50 - 150 * 20) + 2 * 3600, (int) $unitCost);
        $this->assertEquals(1000 - 108, $this->stock($ids['kopi'])['stock']);
        $this->assertEquals(1000 - 300, $this->stock($ids['oat'])['stock']);
        $this->assertEquals(2000, $this->stock($ids['susu'])['stock'], 'pengganti: susu sapi tidak terpotong');
        $this->assertEquals(98, $this->stock($ids['cup'])['stock']);
        $this->assertSame(3, $this->inShop(fn () => DB::table('stock_movements')->where('order_id', $order)->count()), 'susu net 0 tidak dicatat');

        // Bayar ulang (kiriman ulang) tidak memotong dua kali.
        $this->api('POST', "/api/v1/orders/{$order}/void", $this->owner, ['reason' => 'salah input'])->assertOk();
        $this->assertEquals(1000, $this->stock($ids['kopi'])['stock']);
        $this->assertEquals(100, $this->stock($ids['cup'])['stock']);
        $this->assertEquals(200, $this->stock($ids['kopi'])['avg_cost']);
        $this->api('POST', "/api/v1/orders/{$order}/void", $this->owner, ['reason' => 'salah input'])->assertOk();
        $this->assertEquals(1000, $this->stock($ids['kopi'])['stock']);

        $kinds = collect($this->api('GET', "/api/v1/ingredients/{$ids['kopi']}/movements", $this->owner)->assertOk()->json('data.movements'))->pluck('kind');
        $this->assertSame(['void', 'sale', 'purchase'], $kinds->all());
    }

    public function test_stok_boleh_minus_dan_ditandai_menipis(): void
    {
        $ids = $this->stocked();
        $this->api('POST', '/api/v1/stock/waste', $this->owner, ['id' => (string) Str::uuid(), 'note' => 'gelas pecah',
            'lines' => [['ingredient_id' => $ids['cup'], 'qty' => 99]]])->assertCreated();
        $this->sell([], 3, 75000); // cup: 1 − 3 = −2, tetap terjual

        $cup = collect($this->api('GET', '/api/v1/inventory', $this->owner)->json('data.ingredients'))->firstWhere('id', $ids['cup']);
        $this->assertEquals(-2, $cup['stock']);
        $this->assertTrue($cup['low']);
        $this->assertSame(0, $cup['value']);
        $this->assertSame(1, $this->api('GET', '/api/v1/inventory', $this->owner)->json('data.summary.low')); // oat tanpa batas → tidak ditandai
    }

    public function test_terbuang_dan_opname_jadi_kerugian_di_laporan(): void
    {
        $ids = $this->stocked();
        $this->sell([], 1, 25000);
        $this->api('POST', '/api/v1/stock/waste', $this->owner, ['id' => (string) Str::uuid(), 'note' => 'susu basi',
            'lines' => [['ingredient_id' => $ids['susu'], 'qty' => 500]]])->assertCreated(); // 500 × 20 = 10.000
        $this->api('POST', '/api/v1/stock/waste', $this->owner, ['id' => (string) Str::uuid(), 'note' => ' ',
            'lines' => [['ingredient_id' => $ids['susu'], 'qty' => 1]]])->assertUnprocessable();
        // Opname: kopi tercatat 982, dihitung 972 (susut 10 g = 2.000); cup tercatat 99, dihitung 100 (lebih 800).
        $this->api('POST', '/api/v1/stock/counts', $this->owner, ['id' => (string) Str::uuid(), 'lines' => [
            ['ingredient_id' => $ids['kopi'], 'counted' => 972],
            ['ingredient_id' => $ids['cup'], 'counted' => 100],
        ]])->assertCreated();
        $this->assertEquals(972, $this->stock($ids['kopi'])['stock']);

        $today = now($this->shop->tenant->timezone)->toDateString();
        $r = $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)->assertOk()->json('data');
        $this->assertSame(['waste' => 10000, 'count_diff' => -1200, 'loss' => 11200], array_intersect_key($r['stock'], array_flip(['waste', 'count_diff', 'loss'])));
        $this->assertSame(7400, $r['cost']);
        $this->assertSame($r['gross_profit'] - $r['expenses']['total'] - 11200, $r['net_profit']);
        $this->assertSame([], $r['stock']['low']); // susu 1.350 > batas 1.000
    }

    public function test_laporan_tutup_shift_menyebut_stok_menipis(): void
    {
        $ids = $this->stocked();
        $this->api('POST', '/api/v1/stock/waste', $this->owner, ['id' => (string) Str::uuid(), 'note' => 'tumpah',
            'lines' => [['ingredient_id' => $ids['susu'], 'qty' => 1500]]])->assertCreated();
        $shift = $this->api('GET', '/api/v1/shifts/current', $this->cashier)->json('data.id');
        $text = $this->api('GET', "/api/v1/shifts/{$shift}/report", $this->cashier)->assertOk()->json('data.text');
        $this->assertStringContainsString('Stok menipis: Susu 500 ml', $text);
    }
}
