<?php

namespace Tests\Feature;

use App\Enums\BusinessSector;
use App\Enums\SalesMode;
use App\Http\Requests\SignupRequest;
use App\Models\AuditLog;
use App\Models\Device;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use Database\Seeders\FeatureSeeder;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Tests\TestCase;

/** Pendaftaran mandiri usaha baru + tablet pertama. */
class SignupTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(FeatureSeeder::class);
    }

    private function payload(array $override = []): array
    {
        return $override + [
            'owner_name' => 'Wahyu',
            'email' => 'Wahyu@Contoh.id',
            'password' => 'rahasia123',
            'pin' => '482915',
            'business_name' => 'Kopi Senja',
            'sector' => 'coffee_shop',
            'sales_mode' => 'dine_in',
            'outlet_count' => 2,
            'phone' => '0812-3456-7890',
            'address' => "Jl. Mawar No. 1\nMedan",
            'terms' => true,
            'device_id' => (string) Str::uuid(),
        ];
    }

    private function signup(array $override = [])
    {
        return $this->api('POST', '/api/v1/signup', null, $this->payload($override));
    }

    public function test_signup_creates_tenant_owner_settings_and_first_device(): void
    {
        $res = $this->signup()->assertCreated()
            ->assertJsonPath('device.code', 'T1')
            ->assertJsonPath('device.name', 'Tablet 1')
            ->assertJsonPath('tenant.name', 'Kopi Senja');

        $tenant = Tenant::findOrFail($res->json('tenant.id'));
        $this->assertStringStartsWith('kopi-senja-', $tenant->code);
        $this->assertSame(BusinessSector::CoffeeShop, $tenant->sector);
        $this->assertSame(SalesMode::DineIn, $tenant->sales_mode);
        $this->assertSame([2, '081234567890'], [$tenant->outlet_count, $tenant->phone]);
        $this->assertNotNull($tenant->terms_accepted_at);
        $this->assertSame('standard', $tenant->plan->code);

        $this->tenancy()->run($tenant->id, function () use ($res) {
            $owner = User::query()->sole();
            $this->assertSame(['wahyu@contoh.id', 'owner', $owner->id], [$owner->email, $owner->role->value, $res->json('owner_id')]);
            $settings = TenantSetting::query()->sole();
            $this->assertSame(['Kopi Senja', "Jl. Mawar No. 1\nMedan"], [$settings->receipt_name, $settings->receipt_header]);
            $this->assertSame(['tenant.signup', 'device.registered'], AuditLog::query()->orderBy('created_at')->pluck('action')->all());
        });

        // Tablet langsung bisa dipakai: daftar staf lalu login PIN owner.
        $token = $res->json('token');
        $this->api('GET', '/api/v1/auth/staff', $token)->assertOk()->assertJsonPath('data.0.name', 'Wahyu');
        $this->api('POST', '/api/v1/auth/pin', $token, ['user_id' => $res->json('owner_id'), 'pin' => '482915'])->assertOk();
    }

    public function test_owner_can_register_second_tablet_with_auto_name(): void
    {
        $this->signup()->assertCreated();

        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => 'wahyu@contoh.id', 'password' => 'rahasia123', 'device_id' => (string) Str::uuid(),
        ])->assertCreated()->assertJsonPath('device.code', 'T2')->assertJsonPath('device.name', 'Tablet 2');
    }

    public function test_email_already_used_is_rejected(): void
    {
        $this->signup()->assertCreated();

        $this->signup(['email' => 'WAHYU@contoh.id', 'business_name' => 'Lain', 'device_id' => (string) Str::uuid()])
            ->assertUnprocessable()->assertJsonValidationErrors('email');
        $this->assertSame(1, Tenant::count());
    }

    public function test_validation_password_pin_terms_and_enums(): void
    {
        $this->signup([
            'password' => 'pendek',
            'pin' => '123456',
            'terms' => false,
            'sector' => 'pabrik',
            'sales_mode' => 'drive_thru',
            'outlet_count' => 0,
            'phone' => 'bukan nomor',
        ])->assertUnprocessable()->assertJsonValidationErrors(
            ['password', 'pin', 'terms', 'sector', 'sales_mode', 'outlet_count', 'phone']);

        $this->signup(['password' => 'hanyahuruf'])->assertJsonValidationErrors('password');
        $this->assertSame(0, Tenant::count());
    }

    public function test_weak_pins(): void
    {
        foreach (['000000', '111111', '123456', '345678', '987654', '654321'] as $pin) {
            $this->assertTrue(SignupRequest::weakPin($pin), $pin);
        }
        $this->assertFalse(SignupRequest::weakPin('482915'));
        $this->assertFalse(SignupRequest::weakPin('112233'));
    }

    public function test_tenant_cannot_be_hijacked_via_mass_assignment(): void
    {
        $res = $this->signup(['status' => 'suspended', 'plan_id' => (string) Str::uuid(), 'role' => 'cashier', 'code' => 'berrybrew'])
            ->assertCreated();

        $tenant = Tenant::findOrFail($res->json('tenant.id'));
        $this->assertTrue($tenant->isActive());
        $this->assertNotSame('berrybrew', $tenant->code);
    }

    public function test_signup_is_rate_limited_per_ip(): void
    {
        RateLimiter::clear('signup:127.0.0.1');
        for ($i = 0; $i < 5; $i++) {
            $this->signup(['email' => "o{$i}@contoh.id", 'device_id' => (string) Str::uuid()])->assertCreated();
        }
        $this->signup(['email' => 'o9@contoh.id', 'device_id' => (string) Str::uuid()])->assertTooManyRequests();
        $this->assertSame(5, Tenant::count());
    }

    public function test_failed_validation_does_not_use_up_hourly_quota(): void
    {
        for ($i = 0; $i < 6; $i++) {
            $this->signup(['terms' => false])->assertUnprocessable();
        }
        $this->signup()->assertCreated();
    }

    public function test_same_install_retry_reuses_device(): void
    {
        $deviceId = (string) Str::uuid();
        $this->signup(['device_id' => $deviceId])->assertCreated();

        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => 'wahyu@contoh.id', 'password' => 'rahasia123', 'device_id' => $deviceId,
        ])->assertCreated()->assertJsonPath('device.code', 'T1');

        $tenantId = Tenant::query()->sole()->id;
        $this->assertSame(1, $this->tenancy()->run($tenantId, fn () => Device::count()));
    }
}
