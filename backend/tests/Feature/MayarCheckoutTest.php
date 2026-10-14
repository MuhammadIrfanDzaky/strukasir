<?php

namespace Tests\Feature;

use App\Models\Plan;
use App\Support\PlanCatalog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class MayarCheckoutTest extends TestCase
{
    private const KEY = 'mayar-test-key';

    private const TOKEN = 'webhook-rahasia-123';

    private object $shop;

    private string $owner;

    /** Jawaban Mayar untuk GET /invoices/{id} (diubah per tes). */
    private array $gatewayInvoice = ['status' => 'unpaid', 'amount' => 0];

    protected function setUp(): void
    {
        parent::setUp();
        PlanCatalog::sync();
        config(['services.mayar.api_key' => self::KEY, 'services.mayar.sandbox' => true, 'services.mayar.webhook_token' => self::TOKEN,
            'services.mayar.payment_method' => 'qris']);
        $this->shop = $this->makeShop('BerryBrew');
        $tenant = $this->shop->tenant;
        $tenant->plan_id = Plan::where('code', 'gratis')->value('id');
        $tenant->plan_status = 'trial';
        $tenant->plan_ends_at = now()->addDays(3);
        $tenant->save();
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);

        $n = 0;
        Http::fake(function ($request) use (&$n) {
            if (str_ends_with($request->url(), '/invoices/create')) {
                $n++;

                return Http::response(['statusCode' => 200, 'messages' => 'success', 'data' => [
                    'id' => "inv-{$n}", 'transactionId' => "trx-{$n}", 'link' => "https://strukasir.myr.id/invoices/abc{$n}",
                    'expiredAt' => now()->addMinutes(30)->getTimestampMs(),
                ]]);
            }

            return Http::response(['statusCode' => 200, 'messages' => 'success', 'data' => $this->gatewayInvoice + ['id' => 'inv-1']]);
        });
    }

    private function checkout(string $plan = 'tumbuh', string $period = 'month')
    {
        return $this->api('POST', '/api/v1/subscription/checkout', $this->owner, ['plan' => $plan, 'period' => $period]);
    }

    private function webhook(string $token = self::TOKEN, string $productId = 'inv-1')
    {
        return $this->postJson('/api/v1/payments/mayar/webhook?token='.$token, [
            'event' => 'payment.received', 'data' => ['id' => 'wh-1', 'status' => true, 'amount' => 1, 'productId' => $productId],
        ]);
    }

    public function test_owner_membuat_tagihan_dengan_harga_dari_server(): void
    {
        $inv = $this->checkout('tumbuh', 'quarter')->assertCreated()
            ->assertJsonPath('data.amount', 67200)->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.pay_url', 'https://strukasir.myr.id/invoices/abc1')->json('data');

        Http::assertSent(fn ($r) => str_ends_with($r->url(), 'api.mayar.io/hl/v2/invoices/create')
            && $r->hasHeader('Authorization', 'Bearer '.self::KEY)
            && $r['items'][0]['rate'] === 67200 && $r['paymentMethod'] === 'qris' && $r['email'] !== null);
        // Minta lagi paket & periode sama selagi berlaku → tagihan yang sama.
        $this->assertSame($inv['id'], $this->checkout('tumbuh', 'quarter')->json('data.id'));

        $this->api('POST', '/api/v1/subscription/checkout', $this->pinLogin($this->shop), ['plan' => 'tumbuh', 'period' => 'month'])->assertForbidden();
        $this->checkout('gratis')->assertUnprocessable();
    }

    public function test_webhook_mengaktifkan_paket_sekali_saja_dari_status_api(): void
    {
        $inv = $this->checkout()->json('data');
        $this->gatewayInvoice = ['status' => 'paid', 'amount' => 24900];

        $this->webhook()->assertOk();
        $this->webhook()->assertOk(); // dikirim ulang

        $tenant = $this->shop->tenant->refresh();
        $this->assertSame(['tumbuh', 'active'], [$tenant->plan->code, $tenant->plan_status]);
        $this->assertSame(1, DB::table('subscription_payments')->where('tenant_id', $tenant->id)->count());
        $this->api('GET', "/api/v1/subscription/invoices/{$inv['id']}", $this->owner)->assertOk()
            ->assertJsonPath('data.status', 'paid')->assertJsonPath('data.pay_url', null);
    }

    public function test_token_salah_ditolak_dan_isi_webhook_tidak_dipercaya(): void
    {
        $this->checkout();

        $this->webhook('salah')->assertForbidden();
        // Token benar tapi Mayar bilang belum dibayar → tidak aktif.
        $this->webhook()->assertOk();
        $this->assertSame('gratis', $this->shop->tenant->refresh()->plan->code);

        // Jumlah dari Mayar beda dengan tagihan → tidak aktif.
        $this->gatewayInvoice = ['status' => 'paid', 'amount' => 1000];
        $this->webhook()->assertOk();
        $this->assertSame('gratis', $this->shop->tenant->refresh()->plan->code);
    }

    public function test_polling_app_mengaktifkan_paket_bila_webhook_belum_sampai(): void
    {
        $inv = $this->checkout('mulai', 'year')->json('data');
        $this->assertSame(95000, $inv['amount']);

        $this->api('GET', "/api/v1/subscription/invoices/{$inv['id']}", $this->owner)->assertJsonPath('data.status', 'pending');
        $this->gatewayInvoice = ['status' => 'paid', 'amount' => 95000];
        $this->api('GET', "/api/v1/subscription/invoices/{$inv['id']}", $this->owner)->assertJsonPath('data.status', 'paid');

        $tenant = $this->shop->tenant->refresh();
        $this->assertSame(['mulai', 'year'], [$tenant->plan->code, $tenant->plan_period]);
        $this->assertEqualsWithDelta(now()->addYear()->timestamp, $tenant->plan_ends_at->timestamp, 5);

        // Tagihan usaha lain tidak bisa dibuka.
        $other = $this->makeShop('Lain');
        $this->api('GET', "/api/v1/subscription/invoices/{$inv['id']}", $this->pinLogin($other, $other->owner))->assertNotFound();
    }

    public function test_tanpa_kunci_mayar_pembayaran_online_nonaktif(): void
    {
        config(['services.mayar.api_key' => null]);
        $this->checkout()->assertStatus(503);
    }
}
