<?php

namespace Tests\Feature;

use App\Models\Plan;
use App\Models\Tenant;
use App\Support\PlanCatalog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class SubscriptionTest extends TestCase
{
    private object $shop;

    private string $owner;

    protected function setUp(): void
    {
        parent::setUp();
        PlanCatalog::sync();
        $this->shop = $this->makeShop('BerryBrew');
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
    }

    private function onPlan(string $code, string $status = 'trial', ?string $endsIn = '+7 days'): Tenant
    {
        $tenant = $this->shop->tenant->refresh();
        $tenant->plan_id = Plan::where('code', $code)->value('id');
        $tenant->plan_status = $status;
        $tenant->plan_ends_at = $endsIn === null ? null : now()->modify($endsIn);
        $tenant->save();

        return $tenant;
    }

    public function test_status_paket_untuk_sidebar_dan_halaman_upgrade(): void
    {
        $this->onPlan('gratis');

        $res = $this->api('GET', '/api/v1/subscription', $this->pinLogin($this->shop))->assertOk()
            ->assertJsonPath('data.plan.code', 'gratis')
            ->assertJsonPath('data.status', 'trial')
            ->assertJsonPath('data.days_left', 7)
            ->assertJsonPath('data.usage.devices', 1)
            ->assertJsonPath('data.usage.staff', 2)
            ->assertJsonPath('data.plans.*.code', ['gratis', 'mulai', 'tumbuh', 'juragan']);
        $this->assertContains('inventory', $res->json('data.plans.2.features'));
        $this->assertNotContains('inventory', $res->json('data.plans.1.features'));
    }

    public function test_owner_meminta_upgrade_kasir_tidak_boleh(): void
    {
        $this->onPlan('gratis');

        $this->api('POST', '/api/v1/subscription/request', $this->pinLogin($this->shop), ['plan' => 'mulai', 'period' => 'month'])
            ->assertForbidden();
        $this->api('POST', '/api/v1/subscription/request', $this->owner, ['plan' => 'gratis', 'period' => 'month'])
            ->assertUnprocessable()->assertJsonValidationErrors('plan');
        $this->api('POST', '/api/v1/subscription/request', $this->owner, ['plan' => 'standard', 'period' => 'month'])
            ->assertUnprocessable()->assertJsonValidationErrors('plan');

        $this->api('POST', '/api/v1/subscription/request', $this->owner, ['plan' => 'tumbuh', 'period' => 'year'])->assertOk()
            ->assertJsonPath('data.plan.code', 'gratis') // belum aktif sebelum dibayar
            ->assertJsonPath('data.requested.plan.code', 'tumbuh')
            ->assertJsonPath('data.requested.period', 'year');
    }

    public function test_masa_coba_habis_kasir_tidak_bisa_transaksi_baru(): void
    {
        $this->onPlan('gratis', 'trial', '-1 minute');
        $cashier = $this->pinLogin($this->shop);

        $this->api('POST', '/api/v1/shifts/open', $cashier, ['opening_cash' => 0])
            ->assertStatus(402)->assertJsonPath('code', 'plan_expired');
        $this->api('PUT', '/api/v1/orders/'.Str::uuid(), $cashier, ['items' => []])->assertStatus(402);
        // Data & halaman upgrade tetap terbuka.
        $this->api('GET', '/api/v1/subscription', $cashier)->assertOk()->assertJsonPath('data.status', 'expired');
        $this->api('GET', '/api/v1/menu', $cashier)->assertOk();
    }

    public function test_admin_mengaktifkan_paket_setelah_bayar(): void
    {
        $this->onPlan('gratis', 'trial', '-1 day');
        $this->api('POST', '/api/v1/subscription/request', $this->owner, ['plan' => 'mulai', 'period' => 'month'])->assertOk();

        $this->artisan('pos:activate-plan', ['tenant' => $this->shop->tenant->code, 'plan' => 'mulai'])->assertSuccessful();

        $tenant = $this->shop->tenant->refresh();
        $this->assertSame(['mulai', 'active', 'month', null], [$tenant->plan->code, $tenant->plan_status, $tenant->plan_period, $tenant->requested_plan_id]);
        $this->assertEqualsWithDelta(now()->addMonth()->timestamp, $tenant->plan_ends_at->timestamp, 5);
        $this->api('POST', '/api/v1/shifts/open', $this->pinLogin($this->shop), ['opening_cash' => 0])->assertCreated();

        // Perpanjang saat masih aktif: dihitung dari akhir periode berjalan.
        $this->artisan('pos:activate-plan', ['tenant' => $tenant->code, 'plan' => 'mulai'])->assertSuccessful();
        $this->assertEqualsWithDelta(now()->addMonths(2)->timestamp, $tenant->refresh()->plan_ends_at->timestamp, 5);
    }

    public function test_periode_3_6_12_bulan_dengan_diskon_dan_perpanjang_paket_sama(): void
    {
        $this->onPlan('tumbuh', 'active', '+5 days');
        $res = $this->api('GET', '/api/v1/subscription', $this->owner)->assertOk();
        // Tumbuh Rp24.900: 3 bln −10%, 6 bln −15%, 12 bln −20% (dibulatkan ke ratusan).
        $this->assertSame(['month' => 24900, 'quarter' => 67200, 'half' => 127000, 'year' => 239000], $res->json('data.plans.2.prices'));

        // Perpanjang paket yang sedang aktif.
        $this->api('POST', '/api/v1/subscription/request', $this->owner, ['plan' => 'tumbuh', 'period' => 'half'])->assertOk()
            ->assertJsonPath('data.requested.plan.code', 'tumbuh')->assertJsonPath('data.requested.period', 'half');

        $this->artisan('pos:activate-plan', ['tenant' => $this->shop->tenant->code, 'plan' => 'tumbuh', '--period' => 'half'])
            ->expectsOutputToContain('Tagihan: Rp127000')->assertSuccessful();
        $this->assertEqualsWithDelta(now()->addDays(5)->addMonths(6)->timestamp, $this->shop->tenant->refresh()->plan_ends_at->timestamp, 5);
    }

    public function test_batas_pegawai_outlet_dan_tablet_sesuai_paket(): void
    {
        $this->onPlan('gratis'); // owner + 1 pegawai, 1 outlet, 1 tablet

        $this->api('POST', '/api/v1/staff', $this->owner, ['name' => 'Budi', 'pin' => '481526'])
            ->assertUnprocessable()->assertJsonValidationErrors('name');
        $this->api('POST', '/api/v1/outlets', $this->owner, ['name' => 'Cabang 2'])
            ->assertUnprocessable()->assertJsonValidationErrors('name');
        $this->shop->owner->forceFill(['email' => 'owner@berry.id', 'password' => 'rahasia123'])->save();
        $this->api('POST', '/api/v1/devices/register', null, ['email' => 'owner@berry.id', 'password' => 'rahasia123'])
            ->assertUnprocessable()->assertJsonValidationErrors('device');

        $this->onPlan('mulai', 'active', '+1 month'); // 5 pegawai
        $this->api('POST', '/api/v1/staff', $this->owner, ['name' => 'Budi', 'pin' => '481526'])->assertCreated();
    }

    public function test_fitur_di_luar_paket_mati_walau_pernah_dinyalakan(): void
    {
        $this->tenancy()->run($this->shop->tenant->id, fn () => DB::table('tenant_features')->insert([
            'tenant_id' => $this->shop->tenant->id, 'feature_key' => 'inventory', 'enabled' => true, 'created_at' => now(), 'updated_at' => now(),
        ]));
        $this->onPlan('mulai', 'active', '+1 month');

        $this->api('GET', '/api/v1/menu', $this->owner)->assertOk()->assertJsonPath('features.inventory', false);
    }
}
