<?php

namespace Tests\Feature;

use App\Enums\Feature;
use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class AuthTest extends TestCase
{
    private object $shop;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop();
    }

    public function test_owner_registers_a_device_with_email_and_password(): void
    {
        $response = $this->api('POST', '/api/v1/devices/register', null, [
            'email' => $this->shop->owner->email,
            'password' => self::OWNER_PASSWORD,
            'device_name' => 'Tablet Bar',
        ])->assertCreated();

        $this->assertSame('T2', $response->json('device.code'));
        $this->assertNotEmpty($response->json('token'));
        $this->api('GET', '/api/v1/auth/staff', $response->json('token'))->assertOk();
    }

    public function test_registering_twice_with_same_device_id_does_not_duplicate_tablet(): void
    {
        $payload = [
            'email' => $this->shop->owner->email,
            'password' => self::OWNER_PASSWORD,
            'device_name' => 'Tablet Bar',
            'device_id' => (string) Str::uuid(),
        ];

        $first = $this->api('POST', '/api/v1/devices/register', null, $payload)->assertCreated();
        $second = $this->api('POST', '/api/v1/devices/register', null, $payload)->assertCreated();

        $this->assertSame($first->json('device.id'), $second->json('device.id'));
        $this->assertSame('T2', $second->json('device.code'));
        $this->api('GET', '/api/v1/auth/staff', $first->json('token'))->assertUnauthorized(); // token lama diganti
        $this->api('GET', '/api/v1/auth/staff', $second->json('token'))->assertOk();
    }

    public function test_device_registration_rejects_wrong_password_and_cashiers(): void
    {
        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => $this->shop->owner->email, 'password' => 'salah', 'device_name' => 'X',
        ])->assertStatus(422);

        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => 'tidak-ada@contoh.test', 'password' => 'apa saja', 'device_name' => 'X',
        ])->assertStatus(422)->assertJson(['message' => 'Email atau password salah.']);
    }

    public function test_pin_login_returns_token_and_role_permissions(): void
    {
        $response = $this->api('POST', '/api/v1/auth/pin', $this->shop->deviceToken, [
            'user_id' => $this->shop->cashier->id, 'pin' => self::PIN,
        ])->assertOk();

        $permissions = $response->json('user.permissions');
        $this->assertContains('order.create', $permissions);
        $this->assertNotContains('order.void', $permissions);
        $this->assertNotContains('menu.manage', $permissions);

        $this->api('GET', '/api/v1/auth/me', $response->json('token'))
            ->assertOk()
            ->assertJsonPath('device.code', 'T1')
            ->assertJsonPath('features.discounts', true);
    }

    public function test_owner_has_all_permissions(): void
    {
        $token = $this->pinLogin($this->shop, $this->shop->owner);

        $permissions = $this->api('GET', '/api/v1/auth/me', $token)->json('user.permissions');
        $this->assertContains('order.void', $permissions);
        $this->assertContains('menu.manage', $permissions);
    }

    public function test_wrong_pin_locks_account_after_five_attempts(): void
    {
        foreach (range(1, User::MAX_FAILED_ATTEMPTS) as $_) {
            $this->api('POST', '/api/v1/auth/pin', $this->shop->deviceToken, [
                'user_id' => $this->shop->cashier->id, 'pin' => '000000',
            ])->assertStatus(422);
        }

        // PIN benar pun ditolak selama terkunci.
        $this->api('POST', '/api/v1/auth/pin', $this->shop->deviceToken, [
            'user_id' => $this->shop->cashier->id, 'pin' => self::PIN,
        ])->assertStatus(423);
    }

    public function test_failed_pin_is_audited_without_the_pin(): void
    {
        $this->api('POST', '/api/v1/auth/pin', $this->shop->deviceToken, [
            'user_id' => $this->shop->cashier->id, 'pin' => '918273',
        ]);

        $log = $this->tenancy()->run($this->shop->tenant->id,
            fn () => AuditLog::where('action', 'auth.pin_failed')->first());

        $this->assertNotNull($log);
        $this->assertSame($this->shop->device->id, $log->device_id);
        $this->assertStringNotContainsString('918273', json_encode($log->toArray()));
    }

    public function test_device_token_cannot_call_user_endpoints_and_vice_versa(): void
    {
        $this->api('GET', '/api/v1/auth/me', $this->shop->deviceToken)->assertUnauthorized();

        $userToken = $this->pinLogin($this->shop);
        $this->api('GET', '/api/v1/auth/staff', $userToken)->assertUnauthorized();
    }

    public function test_revoking_device_invalidates_its_user_sessions(): void
    {
        $userToken = $this->pinLogin($this->shop);
        $this->shop->device->forceFill(['revoked_at' => now()])->saveQuietly();

        $this->api('GET', '/api/v1/auth/me', $userToken)->assertUnauthorized();
        $this->api('GET', '/api/v1/auth/staff', $this->shop->deviceToken)->assertUnauthorized();
    }

    public function test_logout_revokes_token(): void
    {
        $token = $this->pinLogin($this->shop);

        $this->api('POST', '/api/v1/auth/logout', $token)->assertOk();
        $this->api('GET', '/api/v1/auth/me', $token)->assertUnauthorized();
    }

    public function test_suspended_tenant_is_blocked(): void
    {
        $token = $this->pinLogin($this->shop);
        $this->shop->tenant->forceFill(['status' => 'suspended'])->save();

        $this->api('GET', '/api/v1/auth/me', $token)->assertForbidden();
    }

    public function test_disabling_a_feature_removes_dependent_permissions(): void
    {
        $this->tenancy()->run($this->shop->tenant->id, fn () => DB::table('tenant_features')->insert([
            'tenant_id' => $this->shop->tenant->id, 'feature_key' => Feature::Discounts->value, 'enabled' => false,
        ]));

        $token = $this->pinLogin($this->shop, $this->shop->owner);
        $me = $this->api('GET', '/api/v1/auth/me', $token)->assertOk();

        $this->assertFalse($me->json('features.discounts'));
        $this->assertNotContains('discount.over_limit', $me->json('user.permissions'));
        $this->assertContains('order.void', $me->json('user.permissions'));
    }

    public function test_api_responses_carry_security_headers(): void
    {
        $this->api('GET', '/api/v1/auth/staff', $this->shop->deviceToken)
            ->assertHeader('X-Content-Type-Options', 'nosniff')
            ->assertHeader('X-Frame-Options', 'DENY');

        $this->api('GET', '/api/v1/auth/staff')
            ->assertUnauthorized()
            ->assertHeader('X-Content-Type-Options', 'nosniff');
    }
}
