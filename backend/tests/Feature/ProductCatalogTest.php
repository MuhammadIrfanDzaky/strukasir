<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use Tests\TestCase;

/** Kode produk, harga modal, favorit, dan import CSV. */
class ProductCatalogTest extends TestCase
{
    private object $shop;

    private string $owner;

    private string $category;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->category = $this->api('POST', '/api/v1/categories', $this->owner, ['name' => 'Coffee'])
            ->assertCreated()->json('id');
    }

    private function product(array $data, ?string $token = null, ?string $id = null)
    {
        return $this->api($id ? 'PUT' : 'POST', '/api/v1/products'.($id ? "/{$id}" : ''), $token ?? $this->owner,
            $data + ['category_id' => $this->category, 'name' => 'Americano', 'price' => 15000]);
    }

    private function products(): array
    {
        return $this->tenancy()->run($this->shop->tenant->id, fn () => Product::query()->orderBy('name')->get()->all());
    }

    private function import(string $csv, bool $dryRun = false, ?string $token = null)
    {
        return $this->api('POST', '/api/v1/products/import', $token ?? $this->owner, ['csv' => $csv, 'dry_run' => $dryRun]);
    }

    // ─────────────── kode, modal, favorit ───────────────

    public function test_owner_sets_code_cost_and_favorite_and_cashier_never_sees_cost(): void
    {
        $this->product(['code' => 'BB03', 'cost' => 10000, 'favorite' => true])->assertCreated();

        $this->api('GET', '/api/v1/menu', $this->owner)->assertOk()
            ->assertJsonPath('products.0.code', 'BB03')
            ->assertJsonPath('products.0.cost', 10000)
            ->assertJsonPath('products.0.favorite', true);

        $cashierMenu = $this->api('GET', '/api/v1/menu', $this->pinLogin($this->shop))->assertOk();
        $cashierMenu->assertJsonPath('products.0.favorite', true);
        $this->assertArrayNotHasKey('cost', $cashierMenu->json('products.0'));
    }

    public function test_code_is_unique_per_shop_case_insensitive(): void
    {
        $id = $this->product(['code' => 'BB03'])->assertCreated()->json('id');

        $this->product(['code' => 'bb03', 'name' => 'Latte'])->assertUnprocessable()->assertJsonValidationErrors('code');
        $this->product(['code' => 'BB 03'])->assertUnprocessable()->assertJsonValidationErrors('code');
        $this->product(['code' => 'BB03', 'price' => 16000], id: $id)->assertOk(); // produk sendiri boleh
        $this->product(['code' => ''], id: $id)->assertOk();
        $this->assertNull($this->products()[0]->code);

        // Kedai lain boleh memakai kode yang sama.
        $other = $this->makeShop('Kedai Lain');
        $otherOwner = $this->pinLogin($other, $other->owner);
        $cat = $this->api('POST', '/api/v1/categories', $otherOwner, ['name' => 'Kopi'])->json('id');
        $this->api('POST', '/api/v1/products', $otherOwner, ['category_id' => $cat, 'name' => 'X', 'price' => 1, 'code' => 'BB03'])
            ->assertCreated();
    }

    // ─────────────── import CSV ───────────────

    public function test_import_creates_categories_and_products_from_kloa_style_csv(): void
    {
        $csv = "\xEF\xBB\xBFKode Produk;Nama Produk;Kategori;Harga Jual;Harga Dasar (HPP / Modal);Status;Produk Favorit\n"
            ."BB03;Air Mineral;NON COFFEE;Rp 6.000;Rp 3.000;Aktif;Tidak\n"
            ."BB15;Berrycano;Coffee;22000;19000;aktif;ya\n"
            .'BB99;Lama;Coffee;"10.000";;Nonaktif;'."\n";

        $this->import($csv)->assertOk()
            ->assertJsonPath('data.created', 3)
            ->assertJsonPath('data.updated', 0)
            ->assertJsonPath('data.categories_created', ['NON COFFEE'])
            ->assertJsonPath('data.saved', true);

        [$air, $berry, $lama] = $this->products();
        $this->assertSame(['BB03', 6000, 3000, true, false], [$air->code, $air->price, $air->cost, $air->active, $air->favorite]);
        $this->assertSame(['BB15', 22000, 19000, true], [$berry->code, $berry->price, $berry->cost, $berry->favorite]);
        $this->assertSame([10000, null, false], [$lama->price, $lama->cost, $lama->active]);
        $this->assertSame($this->category, $berry->category_id, 'kategori yang ada dipakai ulang (tanpa beda huruf)');
    }

    public function test_import_updates_by_code_then_by_name(): void
    {
        $byCode = $this->product(['code' => 'BB03', 'name' => 'Air'])->json('id');
        $byName = $this->product(['name' => 'Latte', 'price' => 20000])->json('id');

        $this->import("kode,nama,kategori,harga,modal\nBB03,Air Mineral,Coffee,6000,3000\n,latte,Coffee,21000,9000\n")
            ->assertOk()->assertJsonPath('data.created', 0)->assertJsonPath('data.updated', 2);

        $products = collect($this->products())->keyBy('id');
        $this->assertSame(['Air Mineral', 6000], [$products[$byCode]->name, $products[$byCode]->price]);
        $this->assertSame([21000, 9000], [$products[$byName]->price, $products[$byName]->cost]);
    }

    public function test_import_with_errors_saves_nothing_and_reports_rows(): void
    {
        $csv = "nama,harga,kode\nKopi Susu,18000,K1\n,5000,\nTeh,gratis,\nKopi Susu 2,1,K1\nKopi 3,1,K 3\n";

        $errors = $this->import($csv)->assertUnprocessable()->json('data.errors');

        $this->assertSame([3, 4, 5, 6], array_column($errors, 'row'));
        $this->assertSame([], $this->products());
    }

    public function test_import_requires_name_and_price_columns(): void
    {
        $this->import("kode,kategori\nA1,Kopi\n")->assertUnprocessable()
            ->assertJsonPath('data.errors.0.row', 1);
    }

    public function test_dry_run_previews_without_saving(): void
    {
        $this->import("nama,harga\nKopi Susu,18000\n", dryRun: true)
            ->assertOk()->assertJsonPath('data.created', 1)->assertJsonPath('data.saved', false);

        $this->assertSame([], $this->products());
        $this->assertSame(1, $this->tenancy()->run($this->shop->tenant->id, fn () => Category::count()));
    }

    public function test_cashier_cannot_import(): void
    {
        $this->import("nama,harga\nKopi,1\n", token: $this->pinLogin($this->shop))->assertForbidden();
    }
}
