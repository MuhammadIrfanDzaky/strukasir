<?php

namespace Tests\Feature;

use App\Models\Plan;
use App\Models\Tenant;
use App\Support\PlanCatalog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Tests\TestCase;

class ReferralTest extends TestCase
{
    private object $shop;

    protected function setUp(): void
    {
        parent::setUp();
        PlanCatalog::sync();
        $this->shop = $this->makeShop('BerryBrew');
    }

    private function signup(string $email, array $override = [])
    {
        DB::table('signup_codes')->insert([
            'id' => (string) Str::uuid7(), 'email' => $email, 'code_hash' => Hash::make('135790'),
            'expires_at' => now()->addMinutes(15), 'created_at' => now()->subMinutes(5),
        ]);

        return $this->postJson('/api/v1/signup', [
            'owner_name' => 'Wahyu', 'email' => $email, 'email_code' => '135790', 'password' => 'rahasia123', 'pin' => '482915',
            'business_name' => 'Kopi '.Str::random(4), 'sector' => 'laundry', 'province_code' => '12', 'regency_code' => '12.71',
            'terms' => true, 'device_id' => (string) Str::uuid(), ...$override,
        ]);
    }

    private function activate(Tenant $tenant, string $plan = 'tumbuh'): array
    {
        return app(\App\Services\SubscriptionService::class)->activate($tenant->refresh(), Plan::where('code', $plan)->firstOrFail(), 'month');
    }

    public function test_diajak_dapat_coba_14_hari_dan_diskon_25_persen_sekali(): void
    {
        $code = $this->shop->tenant->refresh()->referral_code;
        $this->assertMatchesRegularExpression('/^[A-Z2-9]{6}$/', $code);

        $res = $this->signup('baru@contoh.id', ['referral_code' => ' '.strtolower($code).' '])->assertCreated();
        $friend = Tenant::findOrFail($res->json('tenant.id'));
        $this->assertSame($this->shop->tenant->id, $friend->referred_by);
        $this->assertEqualsWithDelta(now()->addDays(14)->timestamp, $friend->plan_ends_at->timestamp, 5);

        // Pembayaran pertama: Rp24.900 − 25% → Rp18.700 (dibulatkan ke ratusan). Berikutnya harga normal.
        $this->assertSame(['base' => 24900, 'percent' => 25, 'reason' => 'referred', 'amount' => 18700], $this->activate($friend));
        $this->assertSame(0, $this->activate($friend)['percent']);
    }

    public function test_pengajak_dapat_kupon_50_persen_per_usaha_yang_membayar(): void
    {
        $code = $this->shop->tenant->refresh()->referral_code;
        $a = Tenant::findOrFail($this->signup('a@contoh.id', ['referral_code' => $code])->json('tenant.id'));
        $b = Tenant::findOrFail($this->signup('b@contoh.id', ['referral_code' => $code])->json('tenant.id'));
        $this->signup('c@contoh.id', ['referral_code' => $code])->assertCreated(); // belum bayar → belum ada kupon

        $this->activate($a);
        $this->activate($a); // perpanjangan tidak memberi kupon lagi
        $this->activate($b, 'mulai');

        $owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->api('GET', '/api/v1/subscription', $owner)->assertOk()
            ->assertJsonPath('data.referral.invited', 3)
            ->assertJsonPath('data.referral.paid', 2)
            ->assertJsonPath('data.referral.rewards_available', 2)
            ->assertJsonPath('data.discount.percent', 50);

        // Satu kupon per pembayaran, tidak ditumpuk.
        $this->assertSame(['base' => 49900, 'percent' => 50, 'reason' => 'referral_reward', 'amount' => 25000], $this->activate($this->shop->tenant, 'juragan'));
        $this->assertSame(50, $this->activate($this->shop->tenant, 'juragan')['percent']);
        $this->assertSame(0, $this->activate($this->shop->tenant, 'juragan')['percent']);
    }

    public function test_kode_tidak_dikenal_ditolak(): void
    {
        $this->signup('x@contoh.id', ['referral_code' => 'ZZZZZZ'])->assertUnprocessable()->assertJsonValidationErrors('referral_code');
    }
}
