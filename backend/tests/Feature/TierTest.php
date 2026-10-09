<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class TierTest extends TestCase
{
    private object $shop;

    private string $cashier;

    private string $owner;

    private Product $latte;

    private string $customerId;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->cashier = $this->pinLogin($this->shop);
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->latte = $this->tenancy()->run($this->shop->tenant->id, function () {
            $kopi = Category::create(['name' => 'Kopi']);

            return Product::create(['category_id' => $kopi->id, 'name' => 'Latte', 'price' => 20000]);
        });
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 100000])->assertCreated();
        $this->customerId = $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Andi', 'phone' => '081200000001'])->json('data.id');
    }

    /** Silver: belanja ≥ Rp40.000 → diskon 5%; Gold: ≥ Rp100.000 → diskon 15% & stempel 2×. */
    private function configure(array $override = [])
    {
        return $this->api('PUT', '/api/v1/settings/tiers', $this->owner, [
            'basis' => 'spend',
            'window_months' => 12,
            'tiers' => [
                ['name' => 'Silver', 'threshold' => 40000, 'discount_bp' => 500, 'earn_multiplier' => 1, 'color' => 'silver'],
                ['name' => 'Gold', 'threshold' => 100000, 'discount_bp' => 1500, 'earn_multiplier' => 2, 'color' => 'gold'],
            ],
            ...$override,
        ]);
    }

    private function tierId(string $name): string
    {
        return collect($this->api('GET', '/api/v1/settings/tiers', $this->owner)->json('data.tiers'))->firstWhere('name', $name)['id'];
    }

    private function customer(): array
    {
        return $this->api('GET', '/api/v1/customers?q=Andi', $this->cashier)->json('data.0');
    }

    private function line(int $qty = 1, ?array $discount = null): array
    {
        return ['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => $qty, 'modifier_ids' => [], 'discount' => $discount];
    }

    private function sell(array $items, int $total, ?string $tierId, array $extra = [], ?string $token = null)
    {
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $token ?? $this->cashier, [
            'items' => $items, 'expected_total' => $total, 'customer_id' => $this->customerId, 'tier_id' => $tierId, ...$extra,
        ])->assertOk();

        return $this->api('POST', "/api/v1/orders/{$id}/pay", $token ?? $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => $total, 'tendered' => $total]],
            'expected_total' => $total,
        ])->assertOk();
    }

    public function test_owner_configures_tiers_and_tablets_receive_them(): void
    {
        $this->configure()->assertOk()->assertJsonPath('data.basis', 'spend')->assertJsonPath('data.tiers.1.name', 'Gold');
        $this->api('GET', '/api/v1/menu', $this->cashier)->assertJsonPath('member_tiers.0.name', 'Silver')
            ->assertJsonPath('member_tiers.1.earn_multiplier', 2);

        $this->configure(['tiers' => [['name' => 'Gold', 'threshold' => 100000, 'discount_bp' => 1500, 'earn_multiplier' => 2, 'color' => 'gold']]])
            ->assertOk()->assertJsonCount(1, 'data.tiers');
        $this->api('PUT', '/api/v1/settings/tiers', $this->cashier, [])->assertForbidden();
    }

    public function test_validation(): void
    {
        $tier = ['name' => 'A', 'threshold' => 1000, 'discount_bp' => 500, 'earn_multiplier' => 1, 'color' => 'gold'];
        $this->configure(['tiers' => [$tier, [...$tier, 'name' => 'B']]])->assertUnprocessable()->assertJsonValidationErrors('tiers.1.threshold');
        $this->configure(['tiers' => [[...$tier, 'discount_bp' => 6000]]])->assertUnprocessable()->assertJsonValidationErrors('tiers.0.discount_bp');
        $this->configure(['tiers' => [[...$tier, 'color' => 'pink']]])->assertUnprocessable();
    }

    public function test_tier_rises_with_spending_and_discounts_lines_without_owner_pin(): void
    {
        $this->configure()->assertOk();
        $this->assertNull($this->customer()['tier']);

        $this->sell([$this->line(2)], 40000, null);
        $this->assertSame('Silver', $this->customer()['tier']['name']);

        // Silver 5%: 3 × 20.000 = 60.000 − 3.000.
        $this->sell([$this->line(3)], 57000, $this->tierId('Silver'))
            ->assertJsonPath('data.tier.name', 'Silver')
            ->assertJsonPath('data.tier.discount', 3000)
            ->assertJsonPath('data.items.0.discount', null);
        $this->assertSame('Silver', $this->customer()['tier']['name']); // 97.000 < 100.000
    }

    public function test_gold_discount_exceeds_cashier_limit_without_approval_and_skips_manual_lines(): void
    {
        $this->configure()->assertOk();
        $this->sell([$this->line(5)], 100000, null);
        $gold = $this->tierId('Gold');
        $this->assertSame('Gold', $this->customer()['tier']['name']);

        // Baris diskon manual (Rp1.000) tidak ikut diskon tingkat; baris lain 15%.
        $this->sell([$this->line(1, ['type' => 'amount', 'value' => 1000]), $this->line(1)], 19000 + 17000, $gold)
            ->assertJsonPath('data.tier.discount', 3000)
            ->assertJsonPath('data.items.0.discount.value', 1000);
    }

    public function test_changed_tier_is_detected(): void
    {
        $this->configure()->assertOk();
        $this->api('PUT', '/api/v1/orders/'.Str::uuid(), $this->cashier, [
            'items' => [$this->line()], 'expected_total' => 19000, 'customer_id' => $this->customerId, 'tier_id' => $this->tierId('Silver'),
        ])->assertUnprocessable()->assertJsonValidationErrors('customer_id');
    }

    public function test_gold_earns_double_stamps(): void
    {
        $this->configure()->assertOk();
        $this->api('PUT', '/api/v1/settings/loyalty', $this->owner, [
            'active' => true, 'name' => 'BerryCard', 'earn_mode' => 'per_item',
            'rewards' => [['name' => 'Potongan', 'cost' => 50, 'type' => 'amount', 'value' => 5000]],
        ])->assertOk();
        $this->sell([$this->line(5)], 100000, null)->assertJsonPath('data.loyalty.earned', 5);
        $this->sell([$this->line(1)], 17000, $this->tierId('Gold'))->assertJsonPath('data.loyalty.earned', 2);
    }

    public function test_window_and_visits_basis(): void
    {
        $this->configure()->assertOk();
        $this->sell([$this->line(5)], 100000, null);
        $this->assertSame('Gold', $this->customer()['tier']['name']);

        // Belanja lebih dari 12 bulan lalu tidak dihitung → turun otomatis.
        $this->tenancy()->run($this->shop->tenant->id, fn () => DB::table('orders')->update(['paid_at' => Carbon::now()->subMonths(13)]));
        $this->assertNull($this->customer()['tier']);

        // Dasar kunjungan: 1 order lunas (sepanjang waktu) ≥ ambang 1.
        $this->configure(['basis' => 'visits', 'window_months' => null, 'tiers' => [
            ['name' => 'Langganan', 'threshold' => 1, 'discount_bp' => 0, 'earn_multiplier' => 1, 'color' => 'indigo'],
        ]])->assertOk();
        $this->assertSame('Langganan', $this->customer()['tier']['name']);
    }

    public function test_owner_locks_tier_manually_and_list_filters_by_tier(): void
    {
        $this->configure()->assertOk();
        $gold = $this->tierId('Gold');
        $this->api('PUT', "/api/v1/customers/{$this->customerId}/tier", $this->owner, ['tier_id' => $gold])
            ->assertOk()->assertJsonPath('data.tier.name', 'Gold')->assertJsonPath('data.tier.manual', true);
        $this->api('PUT', "/api/v1/customers/{$this->customerId}/tier", $this->cashier, ['tier_id' => null])->assertForbidden();

        $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Budi', 'phone' => '081200000002'])->assertCreated();
        $names = collect($this->api('GET', "/api/v1/customers?tier_id={$gold}", $this->owner)->json('data'))->pluck('name')->all();
        $this->assertSame(['Andi'], $names);

        $this->api('GET', "/api/v1/customers/{$this->customerId}", $this->owner)
            ->assertJsonPath('data.tier_progress.metric', 0)
            ->assertJsonPath('data.tier_progress.next', null);

        $this->api('PUT', "/api/v1/customers/{$this->customerId}/tier", $this->owner, ['tier_id' => null])
            ->assertOk()->assertJsonPath('data.tier', null);
        $this->api('GET', "/api/v1/customers/{$this->customerId}", $this->owner)
            ->assertJsonPath('data.tier_progress.next.name', 'Silver')
            ->assertJsonPath('data.tier_progress.next.remaining', 40000);
    }

    public function test_feature_off_removes_tiers_and_discounts(): void
    {
        $this->configure()->assertOk();
        $this->sell([$this->line(5)], 100000, null);
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['member_tiers' => false]])->assertOk();

        $this->assertNull($this->customer()['tier']);
        $this->assertSame([], $this->api('GET', '/api/v1/menu', $this->cashier)->json('member_tiers'));
        $this->sell([$this->line(1)], 20000, null)->assertJsonPath('data.tier', null);
        $this->api('GET', '/api/v1/settings/tiers', $this->owner)->assertForbidden();
    }

    public function test_reports_sales_by_tier(): void
    {
        $this->configure()->assertOk();
        $this->sell([$this->line(2)], 40000, null);
        $this->sell([$this->line(1)], 19000, $this->tierId('Silver'));
        $today = now()->toDateString();
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)
            ->assertJsonPath('data.by_tier.0', ['name' => 'Silver', 'orders' => 1, 'sales' => 19000, 'customers' => 1, 'discount' => 1000]);
    }
}
