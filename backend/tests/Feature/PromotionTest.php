<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\Promotion;
use App\Services\PromotionService;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Tests\TestCase;

class PromotionTest extends TestCase
{
    private object $shop;

    private string $cashier;

    private string $owner;

    private Category $kopi;

    private Product $latte;

    private Product $roti;

    protected function setUp(): void
    {
        parent::setUp();
        // Rabu 15:00 WIB.
        Carbon::setTestNow(Carbon::parse('2026-10-14 15:00', 'Asia/Jakarta'));
        $this->shop = $this->makeShop('BerryBrew');
        $this->cashier = $this->pinLogin($this->shop);
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        [$this->kopi, $this->latte, $this->roti] = $this->tenancy()->run($this->shop->tenant->id, function () {
            $kopi = Category::create(['name' => 'Kopi']);
            $makan = Category::create(['name' => 'Makanan']);

            return [
                $kopi,
                Product::create(['category_id' => $kopi->id, 'name' => 'Latte', 'price' => 20000]),
                Product::create(['category_id' => $makan->id, 'name' => 'Roti', 'price' => 10000]),
            ];
        });
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 0])->assertCreated();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function promo(array $data)
    {
        return $this->api('POST', '/api/v1/promotions', $this->owner, [
            'name' => 'Happy Hour', 'type' => 'percent', 'value' => 2000, 'scope' => 'categories', 'target_ids' => [$this->kopi->id],
            'days' => [3], 'start_time' => '14:00', 'end_time' => '17:00', ...$data,
        ]);
    }

    private function voucher(array $data = [])
    {
        return $this->api('POST', '/api/v1/vouchers', $this->owner, [
            'code' => 'hemat10', 'type' => 'percent', 'value' => 1000, 'max_discount' => 5000, 'min_spend' => 30000, ...$data,
        ]);
    }

    private function line(Product $p, int $qty = 1, ?array $discount = null): array
    {
        return ['id' => (string) Str::uuid(), 'product_id' => $p->id, 'qty' => $qty, 'modifier_ids' => [], 'discount' => $discount];
    }

    private function save(array $items, int $total, array $extra = [], ?string $id = null)
    {
        return $this->api('PUT', '/api/v1/orders/'.($id ?? Str::uuid()), $this->cashier, ['items' => $items, 'expected_total' => $total, ...$extra]);
    }

    private function pay(string $id, int $total)
    {
        return $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'qris', 'amount' => $total]], 'expected_total' => $total,
        ]);
    }

    public function test_happy_hour_applies_only_in_its_window_and_category(): void
    {
        $this->promo([])->assertCreated();
        $this->api('GET', '/api/v1/menu', $this->cashier)->assertJsonPath('promotions.0.name', 'Happy Hour')
            ->assertJsonPath('promotions.0.start_time', '14:00');

        // 20% untuk kopi saja; roti tetap.
        $this->save([$this->line($this->latte, 2), $this->line($this->roti)], 42000)
            ->assertOk()
            ->assertJsonPath('data.items.0.promo', 'Happy Hour')
            ->assertJsonPath('data.items.0.discount', null)
            ->assertJsonPath('data.items.0.discount_total', 8000)
            ->assertJsonPath('data.items.1.promo', null)
            ->assertJsonPath('data.promo_discount', 8000);

        Carbon::setTestNow(Carbon::parse('2026-10-14 17:00', 'Asia/Jakarta')); // jam selesai: tidak berlaku
        $this->save([$this->line($this->latte, 2)], 40000)->assertOk();
        Carbon::setTestNow(Carbon::parse('2026-10-14 13:59', 'Asia/Jakarta')); // belum mulai
        $this->save([$this->line($this->latte, 2)], 40000)->assertOk();
    }

    public function test_buy_x_get_y_and_amount_per_item(): void
    {
        $res = $this->promo(['name' => 'Beli 2 gratis 1', 'type' => 'bogo', 'buy_qty' => 2, 'free_qty' => 1, 'scope' => 'products',
            'target_ids' => [$this->latte->id], 'days' => null, 'start_time' => null, 'end_time' => null]);
        $res->assertCreated();
        $res = $this->promo(['name' => 'Roti hemat', 'type' => 'amount', 'value' => 2000, 'scope' => 'all', 'days' => null,
            'start_time' => null, 'end_time' => null]);
        $res->assertCreated();

        // Latte ×5 → 1 set (2+1) → 1 gratis; Rp2.000/item juga berlaku tapi lebih kecil (10.000 < 20.000).
        // Roti ×3 → Rp2.000 × 3.
        $this->save([$this->line($this->latte, 5), $this->line($this->roti, 3)], 80000 + 24000)
            ->assertOk()
            ->assertJsonPath('data.items.0.promo', 'Beli 2 gratis 1')
            ->assertJsonPath('data.items.0.discount_total', 20000)
            ->assertJsonPath('data.items.1.promo', 'Roti hemat')
            ->assertJsonPath('data.items.1.discount_total', 6000);
    }

    public function test_best_of_promo_and_tier_and_manual_discount_wins_its_line(): void
    {
        $this->promo(['value' => 1000])->assertCreated(); // 10%
        $this->api('PUT', '/api/v1/settings/tiers', $this->owner, ['basis' => 'spend', 'window_months' => null, 'tiers' => [
            ['name' => 'Gold', 'threshold' => 0, 'discount_bp' => 1500, 'earn_multiplier' => 1, 'color' => 'gold'],
        ]])->assertOk();
        $gold = $this->api('GET', '/api/v1/settings/tiers', $this->owner)->json('data.tiers.0.id');
        $customer = $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Andi', 'phone' => '081200000001'])->json('data.id');

        // Gold 15% > promo 10% → tingkat; baris diskon manual tidak disentuh.
        $this->save([$this->line($this->latte), $this->line($this->latte, 1, ['type' => 'amount', 'value' => 1000])], 17000 + 19000,
            ['customer_id' => $customer, 'tier_id' => $gold])
            ->assertOk()->assertJsonPath('data.items.0.promo', null)->assertJsonPath('data.tier.discount', 3000)
            ->assertJsonPath('data.items.1.discount.value', 1000);

        $this->api('PUT', '/api/v1/promotions/'.$this->api('GET', '/api/v1/settings/promotions', $this->owner)->json('data.promotions.0.id'),
            $this->owner, ['name' => 'Happy Hour', 'type' => 'percent', 'value' => 5000, 'scope' => 'all'])->assertOk();
        // Promo 50% > Gold 15% → promo, tanpa PIN owner walau melewati batas diskon kasir.
        $this->save([$this->line($this->latte)], 10000, ['customer_id' => $customer, 'tier_id' => $gold])
            ->assertOk()->assertJsonPath('data.items.0.promo', 'Happy Hour');
    }

    public function test_voucher_rules_and_quota(): void
    {
        $this->voucher(['usage_limit' => 1])->assertCreated()->assertJsonPath('data.code', 'HEMAT10');
        $this->api('GET', '/api/v1/vouchers/check?code=Hemat10', $this->cashier)->assertOk()->assertJsonPath('data.max_discount', 5000);
        $this->api('GET', '/api/v1/vouchers/check?code=NGARANG', $this->cashier)->assertUnprocessable()->assertJsonValidationErrors('voucher_code');

        // 10% dari 20.000 di bawah minimal belanja.
        $this->save([$this->line($this->roti, 2)], 20000, ['voucher_code' => 'hemat10'])->assertUnprocessable()->assertJsonValidationErrors('voucher_code');
        // 10% dari 80.000 = 8.000, dibatasi 5.000.
        [$a, $b] = [(string) Str::uuid(), (string) Str::uuid()];
        $this->save([$this->line($this->roti, 8)], 75000, ['voucher_code' => 'HEMAT10'], $a)
            ->assertOk()->assertJsonPath('data.voucher', ['code' => 'HEMAT10', 'discount' => 5000])->assertJsonPath('data.order_discount', null);
        $this->save([$this->line($this->roti, 8)], 75000, ['voucher_code' => 'HEMAT10'], $b)->assertOk();
        $this->pay($a, 75000)->assertOk();
        $this->pay($b, 75000)->assertUnprocessable()->assertJsonValidationErrors('voucher_code'); // kuota habis
        $this->save([$this->line($this->roti, 8)], 75000, ['voucher_code' => 'HEMAT10'])->assertUnprocessable();

        // Void mengembalikan kuota.
        $this->api('POST', "/api/v1/orders/{$a}/void", $this->owner, ['reason' => 'Salah input'])->assertOk();
        $this->pay($b, 75000)->assertOk();
    }

    public function test_voucher_cannot_stack_and_dates_are_checked(): void
    {
        $this->voucher(['code' => 'LAMA', 'ends_on' => '2026-10-13'])->assertCreated();
        $this->voucher(['code' => 'NANTI', 'starts_on' => '2026-10-20'])->assertCreated();
        $this->voucher()->assertCreated();
        $this->save([$this->line($this->roti, 4)], 36000, ['voucher_code' => 'LAMA'])->assertUnprocessable();
        $this->save([$this->line($this->roti, 4)], 36000, ['voucher_code' => 'NANTI'])->assertUnprocessable();
        $this->save([$this->line($this->roti, 4)], 35000, ['voucher_code' => 'HEMAT10', 'order_discount' => ['type' => 'amount', 'value' => 1000]])
            ->assertUnprocessable()->assertJsonValidationErrors('voucher_code');
    }

    public function test_validation_and_owner_only(): void
    {
        $this->promo(['type' => 'bogo', 'buy_qty' => null])->assertUnprocessable()->assertJsonValidationErrors('buy_qty');
        $this->promo(['scope' => 'products', 'target_ids' => []])->assertUnprocessable()->assertJsonValidationErrors('target_ids');
        $this->promo(['value' => 20000])->assertUnprocessable()->assertJsonValidationErrors('value');
        $this->voucher()->assertCreated();
        $this->voucher()->assertUnprocessable()->assertJsonValidationErrors('code');
        $this->voucher(['code' => 'ada spasi'])->assertUnprocessable()->assertJsonValidationErrors('code');
        $this->api('POST', '/api/v1/promotions', $this->cashier, [])->assertForbidden();
        $this->api('GET', '/api/v1/settings/promotions', $this->cashier)->assertForbidden();
    }

    public function test_feature_off_disables_promos_and_vouchers(): void
    {
        $this->promo([])->assertCreated();
        $this->voucher()->assertCreated();
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['promotions' => false]])->assertOk();

        $this->save([$this->line($this->latte, 2)], 40000)->assertOk()->assertJsonPath('data.items.0.promo', null);
        $this->save([$this->line($this->roti, 4)], 36000, ['voucher_code' => 'HEMAT10'])->assertUnprocessable();
        $this->assertSame([], $this->api('GET', '/api/v1/menu', $this->cashier)->json('promotions'));
        $this->api('GET', '/api/v1/settings/promotions', $this->owner)->assertForbidden();
    }

    public function test_reports_promo_and_voucher_usage(): void
    {
        $this->promo([])->assertCreated();
        $this->voucher()->assertCreated();
        $id = (string) Str::uuid();
        // 2 latte (−8.000 promo) + 3 roti = 62.000 → voucher 10% = 5.000 (maks).
        $this->save([$this->line($this->latte, 2), $this->line($this->roti, 3)], 57000, ['voucher_code' => 'HEMAT10'], $id)->assertOk();
        $this->pay($id, 57000)->assertOk();
        $this->api('GET', '/api/v1/reports/summary?from=2026-10-14&to=2026-10-14', $this->owner)
            ->assertJsonPath('data.promotions.promos.0', ['name' => 'Happy Hour', 'qty' => 2, 'discount' => 8000])
            ->assertJsonPath('data.promotions.vouchers.0', ['code' => 'HEMAT10', 'orders' => 1, 'discount' => 5000]);
    }

    public function test_time_window_across_midnight(): void
    {
        $p = new Promotion(['days' => null, 'times' => [['start' => '22:00', 'end' => '02:00']]]);
        $at = fn (string $t) => Carbon::parse("2026-10-14 {$t}", 'Asia/Jakarta');
        $this->assertTrue(PromotionService::runsAt($p, $at('23:30')));
        $this->assertTrue(PromotionService::runsAt($p, $at('01:59')));
        $this->assertFalse(PromotionService::runsAt($p, $at('02:00')));
        $this->assertFalse(PromotionService::runsAt($p, $at('12:00')));

        // Hari: hanya Rabu (14 Okt 2026 = Rabu).
        $wednesday = new Promotion(['days' => [3], 'times' => null]);
        $this->assertTrue(PromotionService::runsAt($wednesday, $at('09:00')));
        $this->assertFalse(PromotionService::runsAt($wednesday, Carbon::parse('2026-10-15 09:00', 'Asia/Jakarta')));
    }

    public function test_several_time_windows_and_legacy_single_window(): void
    {
        $this->promo(['start_time' => null, 'end_time' => null, 'days' => null,
            'times' => [['start' => '19:00', 'end' => '21:00'], ['start' => '12:00', 'end' => '14:00']]])->assertCreated()
            ->assertJsonPath('data.times', [['start' => '12:00', 'end' => '14:00'], ['start' => '19:00', 'end' => '21:00']])
            ->assertJsonPath('data.start_time', '12:00');

        foreach (['12:30' => 32000, '15:00' => 40000, '20:59' => 32000, '21:00' => 40000] as $time => $total) {
            Carbon::setTestNow(Carbon::parse("2026-10-14 {$time}", 'Asia/Jakarta'));
            $this->save([$this->line($this->latte, 2)], $total)->assertOk();
        }
        $this->promo(['times' => [['start' => '10:00', 'end' => '10:00']]])->assertUnprocessable()->assertJsonValidationErrors('times');
        $this->promo(['times' => array_fill(0, 5, ['start' => '10:00', 'end' => '11:00'])])->assertUnprocessable()->assertJsonValidationErrors('times');
    }

    public function test_open_bill_keeps_promo_of_the_time_it_was_ordered(): void
    {
        $this->promo([])->assertCreated(); // Rabu 14:00–17:00
        Carbon::setTestNow(Carbon::parse('2026-10-14 16:55', 'Asia/Jakarta'));
        $id = (string) Str::uuid();
        $this->save([$this->line($this->latte, 2)], 32000, [], $id)->assertOk();

        // Dibayar / ditambah setelah happy hour selesai: tetap pakai jam order dibuat.
        Carbon::setTestNow(Carbon::parse('2026-10-14 17:20', 'Asia/Jakarta'));
        $this->save([$this->line($this->latte, 3)], 48000, [], $id)->assertOk()->assertJsonPath('data.promo_discount', 12000);
        $this->pay($id, 48000)->assertOk();
        // Order baru pada jam yang sama tidak dapat promo.
        $this->save([$this->line($this->latte, 2)], 40000)->assertOk();
        $this->api('GET', '/api/v1/menu', $this->cashier)->assertJsonPath('clock.utc_offset', 420);
    }

    public function test_special_price_and_buy_more(): void
    {
        $this->promo(['name' => 'Latte 15rb', 'type' => 'price', 'value' => 15000, 'scope' => 'products',
            'target_ids' => [$this->latte->id], 'days' => null, 'start_time' => null, 'end_time' => null])->assertCreated();
        $this->promo(['name' => 'Borong roti', 'type' => 'min_qty', 'buy_qty' => 3, 'value' => 1000, 'scope' => 'all',
            'days' => null, 'start_time' => null, 'end_time' => null])->assertCreated();

        // Latte: (20.000 − 15.000) × 2 = 10.000 (lebih besar dari 10% borong yang belum berlaku: qty 2).
        // Roti ×3 → 10% × 30.000 = 3.000.
        $this->save([$this->line($this->latte, 2), $this->line($this->roti, 3)], 30000 + 27000)->assertOk()
            ->assertJsonPath('data.items.0.promo', 'Latte 15rb')
            ->assertJsonPath('data.items.0.discount_total', 10000)
            ->assertJsonPath('data.items.1.promo', 'Borong roti')
            ->assertJsonPath('data.items.1.discount_total', 3000);
        $this->save([$this->line($this->roti, 2)], 20000)->assertOk()->assertJsonPath('data.items.0.promo', null);
        $this->promo(['type' => 'min_qty', 'buy_qty' => 1, 'value' => 1000])->assertUnprocessable()->assertJsonValidationErrors('buy_qty');
    }

    public function test_bundle_price_across_lines(): void
    {
        $bundle = fn (array $extra = []) => $this->promo(['name' => 'Paket Sarapan', 'type' => 'bundle', 'value' => 25000,
            'bundle_items' => [['product_id' => $this->latte->id, 'qty' => 1], ['product_id' => $this->roti->id, 'qty' => 1]],
            'scope' => 'categories', 'days' => null, 'start_time' => null, 'end_time' => null, ...$extra]);
        $bundle(['value' => 30000])->assertUnprocessable()->assertJsonValidationErrors('value'); // tidak lebih murah
        $bundle(['bundle_items' => [['product_id' => $this->latte->id, 'qty' => 1]]])->assertUnprocessable()->assertJsonValidationErrors('bundle_items');
        $bundle()->assertCreated()->assertJsonPath('data.scope', 'all');

        // 2 latte + 1 roti → 1 paket: potongan 5.000 dibagi sebanding harga (latte 3.333, roti 1.667).
        $this->save([$this->line($this->latte, 2), $this->line($this->roti)], 45000)->assertOk()
            ->assertJsonPath('data.items.0.promo', 'Paket Sarapan')
            ->assertJsonPath('data.items.0.discount_total', 3333)
            ->assertJsonPath('data.items.1.promo', 'Paket Sarapan')
            ->assertJsonPath('data.items.1.discount_total', 1667)
            ->assertJsonPath('data.promo_discount', 5000);
        // Isi paket tidak lengkap → tanpa potongan.
        $this->save([$this->line($this->latte, 2)], 40000)->assertOk()->assertJsonPath('data.items.0.promo', null);
        // 2 set.
        $this->save([$this->line($this->roti, 2), $this->line($this->latte, 1), $this->line($this->latte, 1)], 50000)->assertOk()
            ->assertJsonPath('data.promo_discount', 10000);
    }
}
