<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Customer;
use App\Models\Product;
use App\Services\MessagingService;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class MessagingTest extends TestCase
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
            $c = Category::create(['name' => 'Kopi']);

            return Product::create(['category_id' => $c->id, 'name' => 'Latte', 'price' => 20000]);
        });
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 0])->assertCreated();
        $this->customerId = $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Andi', 'phone' => '0812-0000-0001'])->json('data.id');
    }

    private function sell(?string $customerId = null): string
    {
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => 2, 'modifier_ids' => []]],
            'expected_total' => 40000, 'customer_id' => $customerId ?? $this->customerId,
        ])->assertOk();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => 40000, 'tendered' => 40000]],
            'expected_total' => 40000,
        ])->assertOk();

        return $id;
    }

    private function message(string $template, ?string $orderId = null, ?string $token = null, ?string $customerId = null)
    {
        return $this->api('POST', '/api/v1/customers/'.($customerId ?? $this->customerId).'/messages', $token ?? $this->cashier,
            ['template' => $template, 'order_id' => $orderId]);
    }

    public function test_cashier_sends_digital_receipt_via_whatsapp_link(): void
    {
        $orderId = $this->sell();
        $res = $this->message('receipt', $orderId)->assertOk();

        $this->assertStringStartsWith('https://wa.me/6281200000001?text=', $res->json('data.url'));
        $text = $res->json('data.text');
        foreach (['Halo Andi', 'BerryBrew', '2x Latte', 'Total: Rp40.000'] as $part) {
            $this->assertStringContainsString($part, $text);
        }
        $this->assertSame($text, rawurldecode(explode('?text=', $res->json('data.url'))[1]));
        $this->assertSame(1, $this->tenancy()->run($this->shop->tenant->id, fn () => DB::table('message_logs')->where('template', 'receipt')->count()));
    }

    public function test_receipt_only_for_own_paid_order_and_customer_with_phone(): void
    {
        $other = $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Budi', 'phone' => '081200000002'])->json('data.id');
        $this->message('receipt', $this->sell($other))->assertUnprocessable()->assertJsonValidationErrors('order_id');
        $this->message('receipt')->assertUnprocessable();

        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['customer_phone_required' => false])->assertOk();
        $noPhone = $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Citra'])->json('data.id');
        $this->message('greeting', token: $this->owner, customerId: $noPhone)->assertUnprocessable()->assertJsonValidationErrors('customer');
    }

    public function test_other_templates_are_owner_only_and_editable(): void
    {
        $this->message('winback')->assertForbidden();
        $this->message('winback', token: $this->owner)->assertOk();

        $this->api('PUT', '/api/v1/settings/messages', $this->owner, ['templates' => ['greeting' => 'Hai {nama} ({kode}) dari {kedai}']])
            ->assertOk()->assertJsonPath('data.templates.4.body', 'Hai {nama} ({kode}) dari {kedai}');
        $this->message('greeting', token: $this->owner)->assertJsonPath('data.text', 'Hai Andi (M0001) dari BerryBrew');

        // Kosong = kembali ke teks bawaan.
        $this->api('PUT', '/api/v1/settings/messages', $this->owner, ['templates' => ['greeting' => '']])->assertOk()
            ->assertJsonPath('data.templates.4.body', MessagingService::TEMPLATES['greeting'][1]);
        $this->api('PUT', '/api/v1/settings/messages', $this->cashier, ['templates' => ['greeting' => 'x']])->assertForbidden();
    }

    public function test_birthday_audience_covers_next_seven_days(): void
    {
        $today = Carbon::now('Asia/Jakarta');
        $this->tenancy()->run($this->shop->tenant->id, function () use ($today) {
            Customer::whereKey($this->customerId)->update(['birth_date' => $today->copy()->addDays(2)->subYears(30)->toDateString()]);
        });
        $later = $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Nanti', 'phone' => '081200000003',
            'birth_date' => $today->copy()->addDays(20)->subYears(25)->toDateString()])->assertCreated();
        $this->assertNotNull($later->json('data.id'));

        $list = $this->api('GET', '/api/v1/messages/audience?template=birthday', $this->owner)->assertOk()->json('data');
        $this->assertSame(['Andi'], array_column($list, 'name'));
        $this->assertNull($list[0]['last_sent_at']);

        $this->message('birthday', token: $this->owner)->assertOk();
        $this->assertNotNull($this->api('GET', '/api/v1/messages/audience?template=birthday', $this->owner)->json('data.0.last_sent_at'));
        $this->api('GET', '/api/v1/messages/audience?template=birthday', $this->cashier)->assertForbidden();
    }

    public function test_days_until_birthday_handles_month_ends_and_leap_days(): void
    {
        $at = fn (string $d) => Carbon::parse($d, 'Asia/Jakarta');
        $this->assertSame(0, MessagingService::daysUntilBirthday($at('1990-10-09'), $at('2026-10-09 15:00')));
        $this->assertSame(3, MessagingService::daysUntilBirthday($at('1990-12-31'), $at('2026-12-28')));
        $this->assertSame(1, MessagingService::daysUntilBirthday($at('1990-01-01'), $at('2026-12-31')));
        $this->assertSame(0, MessagingService::daysUntilBirthday($at('2000-02-29'), $at('2027-02-28')));
    }

    public function test_winback_and_credit_audiences(): void
    {
        $this->sell();
        $this->tenancy()->run($this->shop->tenant->id, fn () => DB::table('orders')->update(['paid_at' => Carbon::now()->subDays(45)]));
        $this->assertSame(['Andi'], array_column($this->api('GET', '/api/v1/messages/audience?template=winback', $this->owner)->json('data'), 'name'));

        $this->assertSame([], $this->api('GET', '/api/v1/messages/audience?template=credit_reminder', $this->owner)->json('data'));
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => 1, 'modifier_ids' => []]],
            'expected_total' => 20000, 'customer_id' => $this->customerId,
        ])->assertOk();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'credit', 'amount' => 20000]], 'expected_total' => 20000,
        ])->assertOk();
        $this->api('GET', '/api/v1/messages/audience?template=credit_reminder', $this->owner)->assertJsonPath('data.0.credit_balance', 20000);
        $this->assertStringContainsString('Rp20.000', $this->message('credit_reminder', token: $this->owner)->json('data.text'));
    }

    public function test_feature_off_blocks_messaging(): void
    {
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['customer_messaging' => false]])->assertOk();
        $this->message('receipt', $this->sell())->assertForbidden();
        $this->api('GET', '/api/v1/settings/messages', $this->owner)->assertForbidden();
    }
}
