<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Category;
use Tests\TestCase;

class MenuTest extends TestCase
{
    private object $shop;

    private string $ownerToken;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->ownerToken = $this->pinLogin($this->shop, $this->shop->owner);
    }

    /** @return array{category: string, group: string, product: string} */
    private function seedMenu(?string $token = null): array
    {
        $token ??= $this->ownerToken;

        $category = $this->api('POST', '/api/v1/categories', $token, ['name' => 'Kopi'])
            ->assertCreated()->json('id');

        $group = $this->api('POST', '/api/v1/modifier-groups', $token, [
            'name' => 'Suhu', 'min_select' => 1, 'max_select' => 1,
            'modifiers' => [
                ['name' => 'Hot', 'price_delta' => 0],
                ['name' => 'Cold', 'price_delta' => 2000],
            ],
        ])->assertCreated()->json('id');

        $product = $this->api('POST', '/api/v1/products', $token, [
            'category_id' => $category, 'name' => 'Americano', 'price' => 13000,
            'modifier_group_ids' => [$group],
        ])->assertCreated()->json('id');

        return compact('category', 'group', 'product');
    }

    public function test_owner_builds_menu_and_cashier_reads_it(): void
    {
        $ids = $this->seedMenu();
        $cashierToken = $this->pinLogin($this->shop);

        $menu = $this->api('GET', '/api/v1/menu', $cashierToken)->assertOk();

        $menu->assertJsonPath('products.0.name', 'Americano')
            ->assertJsonPath('products.0.price', 13000)
            ->assertJsonPath('products.0.modifier_group_ids', [$ids['group']])
            ->assertJsonPath('modifier_groups.0.modifiers.1.name', 'Cold')
            ->assertJsonPath('modifier_groups.0.modifiers.1.price_delta', 2000)
            ->assertJsonPath('pricing.cashier_discount_limit_bp', 1000)
            ->assertJsonPath('pricing.tax_bp', 0)
            ->assertJsonPath('features.split_payment', true);
        $this->assertNotEmpty($menu->json('version'));
    }

    public function test_cashier_cannot_manage_menu(): void
    {
        $cashierToken = $this->pinLogin($this->shop);

        $this->api('POST', '/api/v1/categories', $cashierToken, ['name' => 'Teh'])->assertForbidden();
    }

    public function test_menu_version_changes_when_menu_changes(): void
    {
        $ids = $this->seedMenu();
        $v1 = $this->api('GET', '/api/v1/menu', $this->ownerToken)->json('version');

        $this->travel(1)->seconds();
        $this->api('PUT', "/api/v1/products/{$ids['product']}", $this->ownerToken, [
            'category_id' => $ids['category'], 'name' => 'Americano', 'price' => 14000,
        ])->assertOk();

        $this->assertNotSame($v1, $this->api('GET', '/api/v1/menu', $this->ownerToken)->json('version'));
    }

    public function test_price_change_is_audited_with_before_and_after(): void
    {
        $ids = $this->seedMenu();

        $this->api('PUT', "/api/v1/products/{$ids['product']}", $this->ownerToken, [
            'category_id' => $ids['category'], 'name' => 'Americano', 'price' => 14000,
        ])->assertOk();

        $log = $this->tenancy()->run($this->shop->tenant->id,
            fn () => AuditLog::where('action', 'product.updated')->first());

        $this->assertSame(13000, $log->before['price']);
        $this->assertSame(14000, $log->after['price']);
        $this->assertSame($this->shop->owner->id, $log->user_id);
    }

    public function test_rejects_negative_price(): void
    {
        $ids = $this->seedMenu();

        $this->api('POST', '/api/v1/products', $this->ownerToken, [
            'category_id' => $ids['category'], 'name' => 'Gratis?', 'price' => -1,
        ])->assertUnprocessable()->assertJsonValidationErrors('price');
    }

    public function test_category_with_products_cannot_be_deleted(): void
    {
        $ids = $this->seedMenu();

        $this->api('DELETE', "/api/v1/categories/{$ids['category']}", $this->ownerToken)->assertStatus(409);
    }

    public function test_omitted_modifiers_are_deactivated_not_deleted(): void
    {
        $ids = $this->seedMenu();
        $menu = $this->api('GET', '/api/v1/menu', $this->ownerToken)->json();
        $hot = $menu['modifier_groups'][0]['modifiers'][0];

        $this->api('PUT', "/api/v1/modifier-groups/{$ids['group']}", $this->ownerToken, [
            'name' => 'Suhu', 'min_select' => 1, 'max_select' => 1,
            'modifiers' => [['id' => $hot['id'], 'name' => 'Hot', 'price_delta' => 0]],
        ])->assertOk();

        $modifiers = $this->api('GET', '/api/v1/menu', $this->ownerToken)->json('modifier_groups.0.modifiers');
        $this->assertCount(2, $modifiers);
        $this->assertFalse(collect($modifiers)->firstWhere('name', 'Cold')['active']);
    }

    public function test_cannot_touch_another_tenants_menu(): void
    {
        $other = $this->makeShop('Kedai Lain');
        $otherIds = $this->seedMenu($this->pinLogin($other, $other->owner));
        $mine = $this->seedMenu();

        // Ubah produk kedai lain lewat ID-nya → 404 (tidak terlihat sama sekali).
        $this->api('PUT', "/api/v1/products/{$otherIds['product']}", $this->ownerToken, [
            'category_id' => $mine['category'], 'name' => 'Diambil alih', 'price' => 1,
        ])->assertNotFound();

        // Pakai kategori / grup modifier kedai lain → ditolak validasi.
        $this->api('POST', '/api/v1/products', $this->ownerToken, [
            'category_id' => $otherIds['category'], 'name' => 'X', 'price' => 1000,
        ])->assertUnprocessable()->assertJsonValidationErrors('category_id');

        $this->api('PUT', "/api/v1/products/{$mine['product']}", $this->ownerToken, [
            'category_id' => $mine['category'], 'name' => 'Americano', 'price' => 13000,
            'modifier_group_ids' => [$otherIds['group']],
        ])->assertUnprocessable()->assertJsonValidationErrors('modifier_group_ids.0');

        $this->api('DELETE', "/api/v1/modifier-groups/{$otherIds['group']}", $this->ownerToken)->assertNotFound();

        // Menu kedai ini tidak memuat apa pun dari kedai lain.
        $names = collect($this->api('GET', '/api/v1/menu', $this->ownerToken)->json('products'))->pluck('id');
        $this->assertFalse($names->contains($otherIds['product']));
    }

    public function test_quantity_group_settings_are_saved_and_published(): void
    {
        $this->api('POST', '/api/v1/modifier-groups', $this->ownerToken, [
            'name' => 'Tambahan', 'min_select' => 0, 'max_select' => 4, 'allow_quantity' => true, 'max_quantity' => 3,
            'modifiers' => [['name' => 'Extra shot', 'price_delta' => 5000]],
        ])->assertCreated();
        $this->api('POST', '/api/v1/modifier-groups', $this->ownerToken, [
            'name' => 'Gula', 'min_select' => 0, 'max_select' => 1, 'allow_quantity' => false, 'max_quantity' => 9,
            'modifiers' => [['name' => 'Less sugar', 'price_delta' => 0]],
        ])->assertCreated();
        $this->api('POST', '/api/v1/modifier-groups', $this->ownerToken, [
            'name' => 'X', 'min_select' => 0, 'max_select' => 1, 'allow_quantity' => true, 'max_quantity' => 21,
            'modifiers' => [['name' => 'Y', 'price_delta' => 0]],
        ])->assertJsonValidationErrors('max_quantity');

        $groups = collect($this->api('GET', '/api/v1/menu', $this->ownerToken)->json('modifier_groups'))->keyBy('name');
        $this->assertSame([true, 3], [$groups['Tambahan']['allow_quantity'], $groups['Tambahan']['max_quantity']]);
        $this->assertSame([false, 1], [$groups['Gula']['allow_quantity'], $groups['Gula']['max_quantity']], 'grup biasa: maks 1');
    }

    public function test_group_assigned_to_categories_and_existing_products(): void
    {
        ['category' => $kopi, 'group' => $suhu, 'product' => $americano] = $this->seedMenu();
        $makanan = $this->api('POST', '/api/v1/categories', $this->ownerToken, ['name' => 'Makanan'])->json('id');
        $roti = $this->api('POST', '/api/v1/products', $this->ownerToken, ['category_id' => $makanan, 'name' => 'Roti', 'price' => 10000])->json('id');
        $other = $this->makeShop('Lain');
        $otherCategory = $this->tenancy()->run($other->tenant->id, fn () => Category::create(['name' => 'Kopi'])->id);

        $payload = ['name' => 'Level pedas', 'min_select' => 1, 'max_select' => 1, 'modifiers' => [['name' => 'Pedas', 'price_delta' => 0]]];
        $this->api('POST', '/api/v1/modifier-groups', $this->ownerToken, [...$payload, 'category_ids' => [$otherCategory]])
            ->assertJsonValidationErrors('category_ids.0'); // kategori usaha lain
        $pedas = $this->api('POST', '/api/v1/modifier-groups', $this->ownerToken, [...$payload, 'category_ids' => [$makanan], 'apply_to_existing' => true])
            ->assertCreated()->json('id');

        $menu = $this->api('GET', '/api/v1/menu', $this->ownerToken);
        $groups = collect($menu->json('modifier_groups'))->keyBy('id');
        $products = collect($menu->json('products'))->keyBy('id');
        $this->assertSame([$makanan], $groups[$pedas]['category_ids']);
        $this->assertSame([], $groups[$suhu]['category_ids'], 'belum diatur');
        $this->assertSame([$pedas], $products[$roti]['modifier_group_ids'], 'produk lama di kategori ikut dipasang');
        $this->assertSame([$suhu], $products[$americano]['modifier_group_ids'], 'kategori lain tidak tersentuh');

        // Ubah tanpa pasang ke produk lama: hanya penanda kategori.
        $this->api('PUT', "/api/v1/modifier-groups/{$suhu}", $this->ownerToken, [
            'name' => 'Suhu', 'min_select' => 1, 'max_select' => 1, 'category_ids' => [$kopi, $makanan],
            'modifiers' => [['name' => 'Hot', 'price_delta' => 0]],
        ])->assertOk();
        $products = collect($this->api('GET', '/api/v1/menu', $this->ownerToken)->json('products'))->keyBy('id');
        $this->assertSame([$pedas], $products[$roti]['modifier_group_ids']);
    }
}
