<?php

namespace Tests\Feature;

use App\Enums\Feature;
use App\Models\AuditLog;
use App\Models\Plan;
use App\Models\Tenant;
use App\Models\TenantSetting;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/** Pengaturan → Fitur: owner menyalakan/mematikan modul kedai dalam batas paket. */
class FeatureSettingsTest extends TestCase
{
    private object $shop;

    private string $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
    }

    private function save(array $data, ?string $token = null)
    {
        return $this->api('PUT', '/api/v1/settings/features', $token ?? $this->owner, $data);
    }

    private function feature(string $key, ?string $token = null): bool
    {
        return (bool) $this->api('GET', '/api/v1/menu', $token ?? $this->owner)->json("features.{$key}");
    }

    public function test_owner_lists_toggleable_features(): void
    {
        $res = $this->api('GET', '/api/v1/settings/features', $this->owner)->assertOk();

        $keys = array_column($res->json('data.features'), 'key');
        $this->assertContains('customer_name', $keys);
        $this->assertNotContains('reports', $keys, 'laporan diatur paket, bukan owner');
        $openBill = collect($res->json('data.features'))->firstWhere('key', 'open_bill');
        $this->assertSame([true, true, 'customer_name'], [$openBill['available'], $openBill['enabled'], $openBill['requires']]);
        $res->assertJsonPath('data.tax_percent', 0);
    }

    public function test_turning_off_a_feature_reaches_tablets_and_is_enforced(): void
    {
        $versionBefore = $this->api('GET', '/api/v1/menu', $this->owner)->json('version');

        $this->save(['features' => ['modifiers' => false, 'split_payment' => false]])->assertOk();

        $menu = $this->api('GET', '/api/v1/menu', $this->pinLogin($this->shop))->assertOk();
        $this->assertFalse($menu->json('features.modifiers'));
        $this->assertFalse($menu->json('features.split_payment'));
        $this->assertTrue($menu->json('features.discounts'), 'fitur lain tidak berubah');
        $this->assertNotSame($versionBefore, $menu->json('version'), 'tablet tahu harus memuat ulang');

        // Nyalakan lagi.
        $this->save(['features' => ['modifiers' => true]])->assertOk();
        $this->assertTrue($this->feature('modifiers'));
    }

    public function test_open_bill_requires_customer_name(): void
    {
        $this->save(['features' => ['customer_name' => false]])
            ->assertUnprocessable()->assertJsonValidationErrors('features.open_bill');

        $this->save(['features' => ['customer_name' => false, 'open_bill' => false]])->assertOk();
        $this->assertFalse($this->feature('customer_name'));

        $this->save(['features' => ['open_bill' => true]])->assertJsonValidationErrors('features.open_bill');
        $this->save(['features' => ['open_bill' => true, 'customer_name' => true]])->assertOk();
    }

    public function test_cannot_turn_off_open_bill_while_bills_are_open(): void
    {
        $category = $this->api('POST', '/api/v1/categories', $this->owner, ['name' => 'Kopi'])->json('id');
        $productId = $this->api('POST', '/api/v1/products', $this->owner, ['category_id' => $category, 'name' => 'Americano', 'price' => 10000])
            ->assertCreated()->json('id');
        $cashier = $this->pinLogin($this->shop);
        $this->api('POST', '/api/v1/shifts/open', $cashier, ['opening_cash' => 0])->assertSuccessful();
        $this->api('PUT', '/api/v1/orders/'.Str::uuid(), $cashier, [
            'customer_label' => 'Meja 3',
            'expected_total' => 10000,
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $productId, 'qty' => 1, 'modifier_ids' => []]],
        ])->assertSuccessful();

        $this->save(['features' => ['open_bill' => false]])
            ->assertUnprocessable()->assertJsonValidationErrors('features.open_bill');
    }

    public function test_cannot_enable_feature_outside_plan(): void
    {
        $plan = Tenant::query()->firstOrFail()->plan;
        DB::table('plan_features')->where('plan_id', $plan->id)->where('feature_key', Feature::SplitPayment->value)->delete();

        $this->save(['features' => ['split_payment' => true]])
            ->assertUnprocessable()->assertJsonValidationErrors('features.split_payment');
        $this->save(['features' => ['split_payment' => false]])->assertOk(); // mematikan tetap boleh
    }

    public function test_unknown_or_plan_only_keys_are_rejected(): void
    {
        $this->save(['features' => ['reports' => false]])->assertJsonValidationErrors('features');
        $this->save(['features' => ['hack' => true]])->assertJsonValidationErrors('features');
        $this->save(['features' => ['discounts' => 'kadang']])->assertJsonValidationErrors('features.discounts');
    }

    public function test_tax_and_service_percent(): void
    {
        $this->save(['tax_percent' => 11, 'service_percent' => 5.5])->assertOk()
            ->assertJsonPath('data.tax_percent', 11)->assertJsonPath('data.service_percent', 5.5);

        $settings = $this->tenancy()->run($this->shop->tenant->id, fn () => TenantSetting::query()->sole());
        $this->assertSame([1100, true, 550, true], [$settings->tax_rate_bp, $settings->tax_enabled, $settings->service_rate_bp, $settings->service_enabled]);

        $this->api('GET', '/api/v1/menu', $this->owner)->assertJsonPath('pricing.tax_bp', 1100);
        // Fitur dimatikan → tidak dipungut walau persen tersimpan.
        $this->save(['features' => ['tax_service' => false]])->assertOk();
        $this->api('GET', '/api/v1/menu', $this->owner)->assertJsonPath('pricing.tax_bp', 0);

        $this->save(['tax_percent' => 0])->assertOk();
        $this->save(['tax_percent' => 101])->assertJsonValidationErrors('tax_percent');
        $this->save(['tax_percent' => 1.234])->assertJsonValidationErrors('tax_percent');
    }

    public function test_cashier_cannot_change_features_and_changes_are_audited(): void
    {
        $cashier = $this->pinLogin($this->shop);
        $this->api('GET', '/api/v1/settings/features', $cashier)->assertForbidden();
        $this->save(['features' => ['discounts' => false]], $cashier)->assertForbidden();

        $this->save(['features' => ['discounts' => false]])->assertOk();
        $log = $this->tenancy()->run($this->shop->tenant->id,
            fn () => AuditLog::query()->where('action', 'settings.features_updated')->sole());
        $this->assertTrue($log->before['features']['discounts']);
        $this->assertFalse($log->after['features']['discounts']);
    }

    public function test_override_is_per_shop(): void
    {
        $other = $this->makeShop('Kedai Lain');
        $this->save(['features' => ['modifiers' => false]])->assertOk();

        $this->assertTrue($this->feature('modifiers', $this->pinLogin($other, $other->owner)));
    }

    public function test_order_keeps_rates_used_at_sale_time(): void
    {
        $this->save(['tax_percent' => 10, 'service_percent' => 5])->assertOk();
        $category = $this->api('POST', '/api/v1/categories', $this->owner, ['name' => 'Kopi'])->json('id');
        $productId = $this->api('POST', '/api/v1/products', $this->owner, ['category_id' => $category, 'name' => 'Americano', 'price' => 10000])->json('id');
        $cashier = $this->pinLogin($this->shop);
        $this->api('POST', '/api/v1/shifts/open', $cashier, ['opening_cash' => 0])->assertSuccessful();

        $order = $this->api('PUT', '/api/v1/orders/'.Str::uuid(), $cashier, [
            'customer_label' => 'Meja 1',
            'expected_total' => 11550,
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $productId, 'qty' => 1, 'modifier_ids' => []]],
        ])->assertSuccessful();

        $this->assertSame([500, 1000], [$order->json('data.service_bp'), $order->json('data.tax_bp')]);

        // Tarif diubah kemudian: order lama tetap menyimpan tarif saat transaksi.
        $this->save(['tax_percent' => 11])->assertOk();
        $this->api('GET', '/api/v1/orders/'.$order->json('data.id'), $cashier)->assertJsonPath('data.tax_bp', 1000);
    }

    public function test_tax_inclusive_prices_keep_menu_price_as_total(): void
    {
        $this->save(['tax_percent' => 10, 'tax_inclusive' => true])->assertOk()
            ->assertJsonPath('data.tax_inclusive', true)->assertJsonPath('data.service_inclusive', false);
        $this->api('GET', '/api/v1/menu', $this->owner)
            ->assertJsonPath('pricing.tax_inclusive', true)->assertJsonPath('pricing.service_inclusive', false);

        $category = $this->api('POST', '/api/v1/categories', $this->owner, ['name' => 'Kopi'])->json('id');
        $productId = $this->api('POST', '/api/v1/products', $this->owner, ['category_id' => $category, 'name' => 'Americano', 'price' => 11000])->json('id');
        $cashier = $this->pinLogin($this->shop);
        $this->api('POST', '/api/v1/shifts/open', $cashier, ['opening_cash' => 0])->assertSuccessful();

        $order = $this->api('PUT', '/api/v1/orders/'.Str::uuid(), $cashier, [
            'customer_label' => 'Meja 1',
            'expected_total' => 11000,
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $productId, 'qty' => 1, 'modifier_ids' => []]],
        ])->assertSuccessful();

        $this->assertSame([11000, 1000, true], [$order->json('data.grand_total'), $order->json('data.tax_total'), $order->json('data.tax_inclusive')]);
    }
}
