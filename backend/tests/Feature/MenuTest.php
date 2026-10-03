<?php

namespace Tests\Feature;

use App\Models\AuditLog;
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
}
