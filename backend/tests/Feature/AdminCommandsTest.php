<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Tenant;
use App\Models\User;
use Database\Seeders\FeatureSeeder;
use Illuminate\Support\Facades\Artisan;
use Tests\TestCase;

class AdminCommandsTest extends TestCase
{
    /** Ambil nilai "  Label: nilai" dari output command. */
    private function grab(string $output, string $label): string
    {
        preg_match('/'.$label.'\s*:\s*(\S+)/', $output, $m);

        return $m[1];
    }

    public function test_create_tenant_provisions_shop_that_can_register_a_tablet(): void
    {
        $this->assertSame(0, Artisan::call('pos:create-tenant', [
            'code' => 'kedai-baru', 'name' => 'Kedai Baru', '--owner-email' => 'Pemilik@Kedai.test',
        ]));
        $output = Artisan::output();
        $password = $this->grab($output, 'Password');

        $tenant = Tenant::where('code', 'kedai-baru')->firstOrFail();
        $this->assertSame('Kedai Baru', $tenant->name);

        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => 'pemilik@kedai.test', 'password' => $password, 'device_name' => 'Tablet',
        ])->assertCreated()->assertJsonPath('tenant.name', 'Kedai Baru');
    }

    public function test_create_tenant_rejects_duplicate_code_and_email(): void
    {
        $this->seed(FeatureSeeder::class);
        Artisan::call('pos:create-tenant', ['code' => 'satu', 'name' => 'Satu', '--owner-email' => 'a@a.test']);

        $this->assertSame(1, Artisan::call('pos:create-tenant', ['code' => 'satu', 'name' => 'Dua', '--owner-email' => 'b@b.test']));
        $this->assertSame(1, Artisan::call('pos:create-tenant', ['code' => 'dua', 'name' => 'Dua', '--owner-email' => 'A@a.test']));
        $this->assertSame(1, Tenant::count());
    }

    public function test_reset_owner_password_revokes_sessions_and_is_audited(): void
    {
        $shop = $this->makeShop();
        $token = $this->pinLogin($shop, $shop->owner);

        $this->assertSame(0, Artisan::call('pos:reset-owner-password', ['email' => $shop->owner->email, '--pin' => true]));
        $output = Artisan::output();

        $this->api('GET', '/api/v1/auth/me', $token)->assertUnauthorized();
        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => $shop->owner->email, 'password' => $this->grab($output, 'Password'), 'device_name' => 'X',
        ])->assertCreated();
        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => $shop->owner->email, 'password' => self::OWNER_PASSWORD, 'device_name' => 'X',
        ])->assertUnprocessable();

        $this->assertTrue($this->tenancy()->run($shop->tenant->id,
            fn () => AuditLog::where('action', 'owner.credentials_reset')->exists()));
    }

    public function test_reset_rejects_non_owner(): void
    {
        $shop = $this->makeShop();
        $cashier = $this->tenancy()->run($shop->tenant->id, fn () => User::find($shop->cashier->id));

        $this->assertSame(1, Artisan::call('pos:reset-owner-password', ['email' => (string) $cashier->email]));
    }

    public function test_app_version_endpoint(): void
    {
        config(['pos.app.min_version' => '1.2.0', 'pos.app.latest_version' => '1.3.0']);

        $this->api('GET', '/api/v1/app/version')
            ->assertOk()
            ->assertJson(['min_version' => '1.2.0', 'latest_version' => '1.3.0']);
    }
}
