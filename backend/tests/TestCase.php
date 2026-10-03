<?php

namespace Tests;

use App\Enums\Feature;
use App\Models\Device;
use App\Models\Plan;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;

abstract class TestCase extends BaseTestCase
{
    use RefreshDatabase;

    protected const OWNER_PASSWORD = 'owner-password-123';

    protected const PIN = '123456';

    protected function tenancy(): TenantContext
    {
        return app(TenantContext::class);
    }

    /**
     * Kedai lengkap: tenant + setting + owner + kasir + tablet terdaftar.
     *
     * @return object{tenant: Tenant, owner: User, cashier: User, device: Device, deviceToken: string}
     */
    protected function makeShop(string $name = 'Kedai'): object
    {
        $plan = Plan::firstOrCreate(['code' => 'test-all'], ['name' => 'Test']);
        foreach (Feature::cases() as $feature) {
            DB::table('features')->insertOrIgnore(['key' => $feature->value, 'description' => $feature->value]);
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $plan->id, 'feature_key' => $feature->value]);
        }

        $tenant = Tenant::factory()->create(['name' => $name, 'plan_id' => $plan->id]);

        return $this->tenancy()->run($tenant->id, function () use ($tenant) {
            (new TenantSetting(['receipt_name' => $tenant->name]))->save();
            $owner = User::factory()->owner(self::OWNER_PASSWORD)->pin(self::PIN)->create(['name' => 'Owner']);
            $cashier = User::factory()->pin(self::PIN)->create(['name' => 'Kasir']);
            $device = Device::factory()->create(['code' => 'T1']);
            $deviceToken = $device->createToken('device:T1', ['device'])->plainTextToken;

            return (object) compact('tenant', 'owner', 'cashier', 'device', 'deviceToken');
        });
    }

    /** Login PIN lewat API dan kembalikan token user. */
    protected function pinLogin(object $shop, ?User $user = null): string
    {
        $response = $this->api('POST', '/api/v1/auth/pin', $shop->deviceToken, [
            'user_id' => ($user ?? $shop->cashier)->id,
            'pin' => self::PIN,
        ])->assertOk();

        return $response->json('token');
    }

    /** Request API dengan bearer token; guard di-reset agar tiap request benar-benar memakai tokennya sendiri. */
    protected function api(string $method, string $uri, ?string $token = null, array $data = []): TestResponse
    {
        $this->app['auth']->forgetGuards();
        $this->tenancy()->clear();

        $headers = ['Accept' => 'application/json'];
        if ($token !== null) {
            $headers['Authorization'] = 'Bearer '.$token;
        }

        return $this->json($method, $uri, $data, $headers);
    }
}
