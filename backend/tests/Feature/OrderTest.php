<?php

namespace Tests\Feature;

use App\Enums\Feature;
use App\Models\AuditLog;
use App\Models\Category;
use App\Models\Modifier;
use App\Models\ModifierGroup;
use App\Models\Order;
use App\Models\Payment;
use App\Models\Product;
use App\Models\TenantSetting;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class OrderTest extends TestCase
{
    private object $shop;

    private string $token;

    private Product $americano;

    private Product $latte;

    private Modifier $hot;

    private Modifier $cold;

    private Modifier $shot;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->token = $this->pinLogin($this->shop);
        $this->api('POST', '/api/v1/shifts/open', $this->token, ['opening_cash' => 200000])->assertCreated();

        $this->inShop(function () {
            $kopi = Category::create(['name' => 'Kopi']);
            $suhu = ModifierGroup::create(['name' => 'Suhu', 'min_select' => 1, 'max_select' => 1]);
            $this->hot = $suhu->modifiers()->create(['name' => 'Hot', 'price_delta' => 0]);
            $this->cold = $suhu->modifiers()->create(['name' => 'Cold', 'price_delta' => 2000]);
            $extra = ModifierGroup::create(['name' => 'Tambahan', 'min_select' => 0, 'max_select' => 2]);
            $this->shot = $extra->modifiers()->create(['name' => 'Extra shot', 'price_delta' => 5000]);

            $this->americano = Product::create(['category_id' => $kopi->id, 'name' => 'Americano', 'price' => 13000]);
            $this->americano->modifierGroups()->sync([
                $suhu->id => ['tenant_id' => $this->shop->tenant->id, 'sort' => 0],
                $extra->id => ['tenant_id' => $this->shop->tenant->id, 'sort' => 1],
            ]);
            $this->latte = Product::create(['category_id' => $kopi->id, 'name' => 'Latte', 'price' => 20000]);
        });
    }

    private function inShop(callable $fn): mixed
    {
        return $this->tenancy()->run($this->shop->tenant->id, $fn);
    }

    private function item(Product $product, array $modifiers = [], int $qty = 1, ?array $discount = null): array
    {
        return [
            'id' => (string) Str::uuid(),
            'product_id' => $product->id,
            'qty' => $qty,
            'modifier_ids' => array_map(fn (Modifier $m) => $m->id, $modifiers),
            'discount' => $discount,
        ];
    }

    private function saveOrder(string $id, array $items, int $expected, array $extra = [], ?string $token = null)
    {
        return $this->api('PUT', "/api/v1/orders/{$id}", $token ?? $this->token,
            ['items' => $items, 'expected_total' => $expected, ...$extra]);
    }

    private function payOrder(string $id, array $payments, int $expected)
    {
        return $this->api('POST', "/api/v1/orders/{$id}/pay", $this->token,
            ['payments' => $payments, 'expected_total' => $expected]);
    }

    private function cash(int $amount, ?int $tendered = null): array
    {
        return ['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => $amount, 'tendered' => $tendered];
    }

    // ─────────────── alur utama ───────────────

    public function test_americano_hot_and_cold_paid_cash_with_change(): void
    {
        $id = (string) Str::uuid();

        $this->saveOrder($id, [$this->item($this->americano, [$this->hot]), $this->item($this->americano, [$this->cold])], 28000)
            ->assertOk()
            ->assertJsonPath('data.status', 'open')
            ->assertJsonPath('data.number', 'T1-0001')
            ->assertJsonPath('data.items.1.modifiers.0.name', 'Cold')
            ->assertJsonPath('data.items.1.line_total', 15000)
            ->assertJsonPath('data.grand_total', 28000);

        $this->payOrder($id, [$this->cash(28000, 30000)], 28000)
            ->assertOk()
            ->assertJsonPath('data.status', 'paid')
            ->assertJsonPath('data.change_total', 2000)
            ->assertJsonPath('data.payments.0.tendered', 30000)
            ->assertJsonPath('data.receipt.name', 'BerryBrew');
    }

    public function test_order_numbers_are_sequential_per_day(): void
    {
        foreach (['T1-0001', 'T1-0002', 'T1-0003'] as $expected) {
            $this->saveOrder((string) Str::uuid(), [$this->item($this->latte)], 20000)
                ->assertOk()->assertJsonPath('data.number', $expected);
        }
    }

    // ─────────────── idempotensi ───────────────

    public function test_resending_the_same_order_does_not_duplicate_it(): void
    {
        $id = (string) Str::uuid();
        $items = [$this->item($this->latte)];

        $this->saveOrder($id, $items, 20000)->assertOk();
        $this->saveOrder($id, $items, 20000)->assertOk()->assertJsonPath('data.number', 'T1-0001');

        $this->assertSame(1, $this->inShop(fn () => Order::count()));
    }

    public function test_resending_the_same_payment_returns_the_paid_order_once(): void
    {
        $id = (string) Str::uuid();
        $this->saveOrder($id, [$this->item($this->latte)], 20000)->assertOk();
        $payment = $this->cash(20000, 50000);

        $this->payOrder($id, [$payment], 20000)->assertOk();
        $this->payOrder($id, [$payment], 20000)->assertOk()->assertJsonPath('data.status', 'paid');

        $this->assertSame(1, $this->inShop(fn () => Payment::count()));
    }

    public function test_paying_twice_with_different_payments_is_rejected(): void
    {
        $id = (string) Str::uuid();
        $this->saveOrder($id, [$this->item($this->latte)], 20000)->assertOk();

        $this->payOrder($id, [$this->cash(20000)], 20000)->assertOk();
        $this->payOrder($id, [$this->cash(20000)], 20000)->assertStatus(409);
    }

    public function test_paid_order_cannot_be_edited(): void
    {
        $id = (string) Str::uuid();
        $this->saveOrder($id, [$this->item($this->latte)], 20000)->assertOk();
        $this->payOrder($id, [$this->cash(20000)], 20000)->assertOk();

        $this->saveOrder($id, [$this->item($this->americano, [$this->hot])], 13000)->assertStatus(409);
    }

    public function test_payment_requires_open_shift(): void
    {
        $id = (string) Str::uuid();
        $this->saveOrder($id, [$this->item($this->latte)], 20000)->assertOk();
        $this->api('POST', '/api/v1/shifts/close', $this->token, ['counted_cash' => 200000])->assertOk();

        $this->payOrder($id, [$this->cash(20000)], 20000)->assertUnprocessable()->assertJsonValidationErrors('shift');
    }

    // ─────────────── harga dihitung server ───────────────

    public function test_stale_tablet_price_is_rejected(): void
    {
        $this->saveOrder((string) Str::uuid(), [$this->item($this->latte)], 18000)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('expected_total');
    }

    public function test_payment_must_match_total_exactly(): void
    {
        $id = (string) Str::uuid();
        $this->saveOrder($id, [$this->item($this->latte)], 20000)->assertOk();

        $this->payOrder($id, [$this->cash(15000)], 20000)->assertUnprocessable()->assertJsonValidationErrors('payments');
        $this->payOrder($id, [$this->cash(20000, 10000)], 20000)->assertUnprocessable();
    }

    public function test_tax_service_and_rounding_follow_shop_settings(): void
    {
        $this->inShop(fn () => TenantSetting::query()->update([
            'service_enabled' => true, 'service_rate_bp' => 500,
            'tax_enabled' => true, 'tax_rate_bp' => 1000, 'rounding_unit' => 500,
        ]));

        // 13000 + 15000 → service 1400, pajak 2940, 32340 → dibulatkan 32500 (lihat pricing-fixtures.json)
        $this->saveOrder((string) Str::uuid(), [$this->item($this->americano, [$this->hot]), $this->item($this->americano, [$this->cold])], 32500)
            ->assertOk()
            ->assertJsonPath('data.service_total', 1400)
            ->assertJsonPath('data.tax_total', 2940)
            ->assertJsonPath('data.rounding', 160);
    }

    public function test_split_payment_cash_and_qris(): void
    {
        $id = (string) Str::uuid();
        $this->saveOrder($id, [$this->item($this->latte, qty: 2)], 40000)->assertOk();

        $this->payOrder($id, [
            $this->cash(25000, 30000),
            ['id' => (string) Str::uuid(), 'method' => 'qris', 'amount' => 15000],
        ], 40000)
            ->assertOk()
            ->assertJsonCount(2, 'data.payments')
            ->assertJsonPath('data.change_total', 5000);

        $qris = $this->inShop(fn () => Payment::where('method', 'qris')->first());
        $this->assertSame($this->shop->cashier->id, $qris->confirmed_by); // siapa yang konfirmasi QRIS tercatat
    }

    public function test_split_payment_requires_feature(): void
    {
        $this->disable(Feature::SplitPayment);
        $id = (string) Str::uuid();
        $this->saveOrder($id, [$this->item($this->latte, qty: 2)], 40000)->assertOk();

        $this->payOrder($id, [$this->cash(20000), ['id' => (string) Str::uuid(), 'method' => 'debit', 'amount' => 20000]], 40000)
            ->assertUnprocessable();
    }

    // ─────────────── validasi menu & modifier ───────────────

    public function test_required_modifier_must_be_chosen(): void
    {
        $this->saveOrder((string) Str::uuid(), [$this->item($this->americano)], 13000)
            ->assertUnprocessable()->assertJsonValidationErrors('items.0.modifier_ids');
    }

    public function test_same_modifier_on_different_items_is_allowed(): void
    {
        // Regresi: dua item dengan pilihan "Cold" yang sama dulu ditolak sebagai duplikat.
        $this->saveOrder((string) Str::uuid(), [
            $this->item($this->americano, [$this->cold]),
            $this->item($this->americano, [$this->cold, $this->shot]),
        ], 35000)->assertOk()->assertJsonPath('data.grand_total', 35000);
    }

    public function test_duplicate_modifier_within_one_item_is_rejected(): void
    {
        $this->saveOrder((string) Str::uuid(), [$this->item($this->americano, [$this->cold, $this->cold])], 17000)
            ->assertUnprocessable()->assertJsonValidationErrors('items.0.modifier_ids');
    }

    public function test_quantity_group_allows_repeating_an_option(): void
    {
        $this->inShop(fn () => ModifierGroup::query()->where('name', 'Tambahan')
            ->update(['allow_quantity' => true, 'max_quantity' => 2]));

        // Americano 13.000 + Cold 2.000 + Extra shot 5.000 x2.
        $res = $this->saveOrder((string) Str::uuid(), [$this->item($this->americano, [$this->cold, $this->shot, $this->shot])], 25000)
            ->assertOk()->assertJsonPath('data.grand_total', 25000);
        $shot = collect($res->json('data.items.0.modifiers'))->firstWhere('name', 'Extra shot');
        $this->assertSame([5000, 2], [$shot['price_delta'], $shot['qty']]);

        // Lebih dari maks. per opsi → ditolak.
        $this->saveOrder((string) Str::uuid(), [$this->item($this->americano, [$this->cold, $this->shot, $this->shot, $this->shot])], 30000)
            ->assertUnprocessable()->assertJsonValidationErrors('items.0.modifier_ids');
    }

    public function test_repeating_option_in_normal_group_is_rejected(): void
    {
        $this->saveOrder((string) Str::uuid(), [$this->item($this->americano, [$this->cold, $this->shot, $this->shot])], 25000)
            ->assertUnprocessable()->assertJsonValidationErrors('items.0.modifier_ids');
    }

    public function test_quantity_counts_toward_group_maximum(): void
    {
        // Tambahan: maks. total 2, tiap opsi maks. 5 → 3 shot tetap ditolak oleh batas total grup.
        $this->inShop(fn () => ModifierGroup::query()->where('name', 'Tambahan')
            ->update(['allow_quantity' => true, 'max_quantity' => 5]));

        $this->saveOrder((string) Str::uuid(), [$this->item($this->americano, [$this->cold, $this->shot, $this->shot, $this->shot])], 30000)
            ->assertUnprocessable()->assertJsonValidationErrors('items.0.modifier_ids');
    }

    public function test_modifier_of_another_product_is_rejected(): void
    {
        $this->saveOrder((string) Str::uuid(), [$this->item($this->latte, [$this->shot])], 25000)
            ->assertUnprocessable()->assertJsonValidationErrors('items.0.modifier_ids');
    }

    public function test_sold_out_product_cannot_be_added(): void
    {
        $this->inShop(fn () => $this->latte->forceFill(['sold_out' => true])->save());

        $this->saveOrder((string) Str::uuid(), [$this->item($this->latte)], 20000)
            ->assertUnprocessable()->assertJsonValidationErrors('items.0.product_id');
    }

    // ─────────────── diskon ───────────────

    public function test_cashier_discount_within_limit_is_allowed(): void
    {
        // Batas default kasir 10%.
        $this->saveOrder((string) Str::uuid(), [$this->item($this->latte, discount: ['type' => 'percent', 'value' => 1000])], 18000)
            ->assertOk()->assertJsonPath('data.discount_total', 2000);
    }

    public function test_cashier_discount_over_limit_needs_owner_pin(): void
    {
        $items = [$this->item($this->latte, discount: ['type' => 'percent', 'value' => 5000])];
        $id = (string) Str::uuid();

        $this->saveOrder($id, $items, 10000)->assertUnprocessable()->assertJsonValidationErrors('approval');

        $this->saveOrder($id, $items, 10000, ['approval' => ['user_id' => $this->shop->owner->id, 'pin' => '000000']])
            ->assertUnprocessable()->assertJsonValidationErrors('approval');

        $this->saveOrder($id, $items, 10000, ['approval' => ['user_id' => $this->shop->owner->id, 'pin' => self::PIN]])
            ->assertOk()->assertJsonPath('data.grand_total', 10000);

        $log = $this->inShop(fn () => AuditLog::where('action', 'discount.approved')->first());
        $this->assertSame($this->shop->owner->id, $log->after['approver_id']);
        $this->assertSame($this->shop->cashier->id, $log->user_id);

        // Percobaan PIN salah tetap tercatat walau request ditolak.
        $this->assertSame(1, $this->inShop(fn () => AuditLog::where('action', 'approval.pin_failed')->count()));
    }

    public function test_cashier_cannot_approve_own_discount(): void
    {
        $other = $this->inShop(fn () => User::factory()->pin(self::PIN)->create(['name' => 'Kasir 2']));

        $this->saveOrder((string) Str::uuid(), [$this->item($this->latte, discount: ['type' => 'percent', 'value' => 5000])], 10000,
            ['approval' => ['user_id' => $other->id, 'pin' => self::PIN]])
            ->assertUnprocessable()->assertJsonValidationErrors('approval');
    }

    public function test_discount_rejected_when_feature_disabled(): void
    {
        $this->disable(Feature::Discounts);

        $this->saveOrder((string) Str::uuid(), [$this->item($this->latte, discount: ['type' => 'amount', 'value' => 1000])], 19000)
            ->assertUnprocessable()->assertJsonValidationErrors('discount');
    }

    // ─────────────── isolasi ───────────────

    public function test_cannot_order_or_pay_across_tenants(): void
    {
        $other = $this->makeShop('Kedai Lain');
        $otherToken = $this->pinLogin($other);
        $id = (string) Str::uuid();
        $this->saveOrder($id, [$this->item($this->latte)], 20000)->assertOk();

        // Produk kedai ini tidak dikenal oleh kedai lain.
        $this->saveOrder((string) Str::uuid(), [$this->item($this->latte)], 20000, token: $otherToken)
            ->assertUnprocessable()->assertJsonValidationErrors('items.0.product_id');

        // Order kedai ini tidak terlihat / tidak bisa dibayar kedai lain.
        $this->api('GET', "/api/v1/orders/{$id}", $otherToken)->assertNotFound();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $otherToken, [
            'payments' => [$this->cash(20000)], 'expected_total' => 20000,
        ])->assertNotFound();

        // UUID yang sama dipakai kedai lain → tidak boleh menimpa order kedai ini.
        $this->tenancy()->clear();
        $this->assertSame('open', $this->tenancy()->run($this->shop->tenant->id, fn () => Order::find($id)->status));
    }

    public function test_open_orders_list(): void
    {
        $open = (string) Str::uuid();
        $paid = (string) Str::uuid();
        $this->saveOrder($open, [$this->item($this->latte)], 20000, ['customer_label' => 'Meja 3'])->assertOk();
        $this->saveOrder($paid, [$this->item($this->latte)], 20000)->assertOk();
        $this->payOrder($paid, [$this->cash(20000)], 20000)->assertOk();

        $this->api('GET', '/api/v1/orders?status=open', $this->token)
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.customer_label', 'Meja 3');
    }

    private function disable(Feature $feature): void
    {
        $this->inShop(fn () => DB::table('tenant_features')->insert([
            'tenant_id' => $this->shop->tenant->id, 'feature_key' => $feature->value, 'enabled' => false,
        ]));
    }
}
