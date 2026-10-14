<?php

namespace Tests\Feature;

use App\Models\Plan;
use App\Support\PlanCatalog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class MidtransCheckoutTest extends TestCase
{
    private const KEY = 'SB-Mid-server-TESTKEY';

    private object $shop;

    private string $owner;

    /** Status yang dijawab Midtrans untuk GET /status (diubah per tes). */
    private array $gatewayStatus = ['transaction_status' => 'pending'];

    protected function setUp(): void
    {
        parent::setUp();
        PlanCatalog::sync();
        config(['services.midtrans.server_key' => self::KEY, 'services.midtrans.production' => false]);
        $this->shop = $this->makeShop('BerryBrew');
        $tenant = $this->shop->tenant;
        $tenant->plan_id = Plan::where('code', 'gratis')->value('id');
        $tenant->plan_status = 'trial';
        $tenant->plan_ends_at = now()->addDays(3);
        $tenant->save();
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);

        Http::fake(function ($request) {
            if (str_ends_with($request->url(), '/v2/charge')) {
                return Http::response([
                    'status_code' => '201', 'transaction_id' => 'trx-1', 'order_id' => $request['transaction_details']['order_id'],
                    'gross_amount' => $request['transaction_details']['gross_amount'].'.00', 'transaction_status' => 'pending',
                    'qr_string' => '00020101021226QRIS', 'expiry_time' => now('Asia/Jakarta')->addMinutes(15)->format('Y-m-d H:i:s'),
                    'actions' => [['name' => 'generate-qr-code', 'method' => 'GET', 'url' => 'https://api.sandbox.midtrans.com/v2/qris/trx-1/qr-code']],
                ], 200);
            }

            return Http::response($this->gatewayStatus + ['status_code' => '200'], 200);
        });
    }

    private function checkout(string $plan = 'tumbuh', string $period = 'month')
    {
        return $this->api('POST', '/api/v1/subscription/checkout', $this->owner, ['plan' => $plan, 'period' => $period]);
    }

    private function notify(array $invoice, string $status, ?string $amount = null, ?string $signature = null)
    {
        $payload = ['order_id' => DB::table('subscription_invoices')->where('id', $invoice['id'])->value('order_id'),
            'status_code' => '200', 'gross_amount' => $amount ?? $invoice['amount'].'.00', 'transaction_status' => $status];
        $payload['signature_key'] = $signature ?? hash('sha512', $payload['order_id'].$payload['status_code'].$payload['gross_amount'].self::KEY);

        return $this->postJson('/api/v1/payments/midtrans/notification', $payload);
    }

    public function test_owner_membuat_qris_dengan_harga_dari_server(): void
    {
        $inv = $this->checkout('tumbuh', 'quarter')->assertCreated()
            ->assertJsonPath('data.amount', 67200)->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.qr_url', 'https://api.sandbox.midtrans.com/v2/qris/trx-1/qr-code')->json('data');

        Http::assertSent(fn ($r) => str_ends_with($r->url(), '/v2/charge') && $r['payment_type'] === 'qris'
            && $r['transaction_details']['gross_amount'] === 67200 && $r->hasHeader('Authorization', 'Basic '.base64_encode(self::KEY.':')));
        // Minta lagi paket & periode sama selagi QR berlaku → QR yang sama.
        $this->assertSame($inv['id'], $this->checkout('tumbuh', 'quarter')->json('data.id'));

        $this->api('POST', '/api/v1/subscription/checkout', $this->pinLogin($this->shop), ['plan' => 'tumbuh', 'period' => 'month'])->assertForbidden();
        $this->checkout('gratis')->assertUnprocessable();
    }

    public function test_notifikasi_lunas_mengaktifkan_paket_sekali_saja(): void
    {
        $inv = $this->checkout()->json('data');
        $this->gatewayStatus = ['transaction_status' => 'settlement', 'gross_amount' => '24900.00', 'order_id' => 'x'];

        $this->notify($inv, 'settlement')->assertOk();
        $this->notify($inv, 'settlement')->assertOk(); // dikirim ulang

        $tenant = $this->shop->tenant->refresh();
        $this->assertSame(['tumbuh', 'active'], [$tenant->plan->code, $tenant->plan_status]);
        $this->assertSame(1, DB::table('subscription_payments')->where('tenant_id', $tenant->id)->count());
        $this->api('GET', "/api/v1/subscription/invoices/{$inv['id']}", $this->owner)->assertOk()
            ->assertJsonPath('data.status', 'paid')->assertJsonPath('data.qr_string', null);
    }

    public function test_tanda_tangan_salah_ditolak_dan_isi_notifikasi_tidak_dipercaya(): void
    {
        $inv = $this->checkout()->json('data');

        $this->notify($inv, 'settlement', signature: str_repeat('a', 128))->assertForbidden();
        // Tanda tangan benar tapi Midtrans sendiri bilang masih pending → tidak aktif.
        $this->notify($inv, 'settlement')->assertOk();
        $this->assertSame('gratis', $this->shop->tenant->refresh()->plan->code);

        // Jumlah dari Midtrans beda dengan tagihan → tidak aktif.
        $this->gatewayStatus = ['transaction_status' => 'settlement', 'gross_amount' => '1000.00'];
        $this->notify($inv, 'settlement')->assertOk();
        $this->assertSame('gratis', $this->shop->tenant->refresh()->plan->code);
    }

    public function test_polling_app_mengaktifkan_paket_bila_notifikasi_belum_sampai(): void
    {
        $inv = $this->checkout('mulai', 'year')->json('data');
        $this->assertSame(95000, $inv['amount']);

        $this->api('GET', "/api/v1/subscription/invoices/{$inv['id']}", $this->owner)->assertJsonPath('data.status', 'pending');
        $this->gatewayStatus = ['transaction_status' => 'settlement', 'gross_amount' => '95000.00'];
        $this->api('GET', "/api/v1/subscription/invoices/{$inv['id']}", $this->owner)->assertJsonPath('data.status', 'paid');

        $tenant = $this->shop->tenant->refresh();
        $this->assertSame(['mulai', 'year'], [$tenant->plan->code, $tenant->plan_period]);
        $this->assertEqualsWithDelta(now()->addYear()->timestamp, $tenant->plan_ends_at->timestamp, 5);

        // Tagihan usaha lain tidak bisa dibuka.
        $other = $this->makeShop('Lain');
        $this->api('GET', "/api/v1/subscription/invoices/{$inv['id']}", $this->pinLogin($other, $other->owner))->assertNotFound();
    }

    public function test_tanpa_kunci_midtrans_pembayaran_online_nonaktif(): void
    {
        config(['services.midtrans.server_key' => null]);
        $this->checkout()->assertStatus(503);
    }
}
