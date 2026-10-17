<?php

namespace Tests\Feature;

use App\Enums\BusinessSector;
use App\Enums\SalesMode;
use App\Http\Requests\SignupRequest;
use App\Mail\EmailCodeMail;
use App\Models\AuditLog;
use App\Models\Device;
use App\Models\Outlet;
use App\Models\Plan;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use Database\Seeders\FeatureSeeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
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
            'province_code' => '12',
            'regency_code' => '12.71',
            'phone' => '0812-3456-7890',
            'address' => "Jl. Mawar No. 1\nMedan",
            'terms' => true,
            'device_id' => (string) Str::uuid(),
        ];
    }

    private function signup(array $override = [])
    {
        $payload = $this->payload($override);
        if (! array_key_exists('email_code', $override) && is_string($payload['email'] ?? null)) {
            $payload['email_code'] = $this->signupCode($payload['email']);
        }

        return $this->api('POST', '/api/v1/signup', null, $payload);
    }

    /** Kode verifikasi email yang valid (langsung di DB, tanpa kirim email). */
    private function signupCode(string $email, string $code = '135790'): string
    {
        DB::table('signup_codes')->insert([
            'id' => (string) Str::uuid7(), 'email' => strtolower(trim($email)), 'code_hash' => Hash::make($code),
            'expires_at' => now()->addMinutes(15), 'created_at' => now()->subMinutes(5),
        ]);

        return $code;
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
        $this->assertSame([null, '081234567890'], [$tenant->outlet_count, $tenant->phone]);
        $this->assertSame(['12', '12.71', null], [$tenant->province_code, $tenant->regency_code, $tenant->sector_other]);
        $this->assertNotNull($tenant->terms_accepted_at);
        // Tanpa pilihan paket = Gratis, masa coba 7 hari.
        $this->assertSame(['gratis', 'trial', null], [$tenant->plan->code, $tenant->plan_status, $tenant->plan_period]);
        $this->assertEqualsWithDelta(now()->addDays(7)->timestamp, $tenant->plan_ends_at->timestamp, 60);

        $this->tenancy()->run($tenant->id, function () use ($res) {
            $owner = User::query()->sole();
            $this->assertSame(['wahyu@contoh.id', 'owner', $owner->id], [$owner->email, $owner->role->value, $res->json('owner_id')]);
            // Alamat & no HP dari form daftar tersalin ke outlet utama.
            $outlet = Outlet::query()->sole();
            $this->assertSame(['O1', 'Kopi Senja', "Jl. Mawar No. 1\nMedan", '081234567890'],
                [$outlet->code, $outlet->name, $outlet->address, $outlet->phone]);
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
        $this->signup(['plan' => 'mulai'])->assertCreated();

        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => 'wahyu@contoh.id', 'password' => 'rahasia123', 'device_id' => (string) Str::uuid(),
        ])->assertCreated()->assertJsonPath('device.code', 'T2')->assertJsonPath('device.name', 'Tablet 2');
    }

    public function test_free_plan_allows_one_tablet_only(): void
    {
        $this->signup()->assertCreated();

        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => 'wahyu@contoh.id', 'password' => 'rahasia123', 'device_id' => (string) Str::uuid(),
        ])->assertUnprocessable()->assertJsonValidationErrors('device');
    }

    public function test_paid_plan_chosen_at_signup_awaits_payment(): void
    {
        $res = $this->signup(['plan' => 'tumbuh', 'period' => 'year'])->assertCreated();

        $tenant = Tenant::findOrFail($res->json('tenant.id'));
        $this->assertSame(['tumbuh', 'awaiting_payment', 'year', 'tumbuh'],
            [$tenant->plan->code, $tenant->plan_status, $tenant->plan_period, $tenant->requestedPlan->code]);
        $this->assertTrue($tenant->plan_ends_at->isFuture());

        $this->signup(['plan' => 'standard', 'email' => 'lain@contoh.id'])->assertJsonValidationErrors('plan');
    }

    public function test_options_list_public_plans(): void
    {
        $this->getJson('/api/v1/signup/options')->assertOk()
            ->assertJsonPath('plans.*.code', ['gratis', 'mulai', 'tumbuh', 'juragan'])
            ->assertJsonPath('plans.0.trial_days', 7)
            ->assertJsonPath('plans.2.recommended', true)
            ->assertJsonPath('plans.1.price_month', 9900);
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
            'phone' => 'bukan nomor',
        ])->assertUnprocessable()->assertJsonValidationErrors(
            ['password', 'pin', 'terms', 'sector', 'sales_mode', 'phone']);

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

    // ─────────────── template jenis usaha ───────────────

    private function menuAfterSignup(array $override): TestResponse
    {
        $res = $this->signup($override + ['device_id' => (string) Str::uuid()])->assertCreated();
        $token = $res->json('token');
        $user = $this->api('POST', '/api/v1/auth/pin', $token, ['user_id' => $res->json('owner_id'), 'pin' => '482915'])->json('token');

        return $this->api('GET', '/api/v1/menu', $user)->assertOk();
    }

    public function test_street_food_takeaway_gets_fast_cashier_template(): void
    {
        $menu = $this->menuAfterSignup(['sector' => 'street_food', 'sales_mode' => 'takeaway']);

        $this->assertEquals( // urutan kunci tidak penting
            ['customer_name' => false, 'open_bill' => false, 'modifiers' => true, 'discounts' => true, 'tax_service' => false, 'split_payment' => true],
            collect($menu->json('features'))->only(['customer_name', 'open_bill', 'modifiers', 'discounts', 'tax_service', 'split_payment'])->all(),
        );
        $this->assertSame(['Makanan', 'Minuman'], array_column($menu->json('categories'), 'name'));
        $this->assertSame([], $menu->json('products'), 'kategori awal kosong, tanpa produk contoh');
        $menu->assertJsonPath('customer_label_hint', 'Nama pelanggan');
        $menu->assertJsonPath('order_types', ['enabled' => false, 'default' => 'takeaway']);
    }

    public function test_coffee_shop_dine_in_gets_table_service_template(): void
    {
        $menu = $this->menuAfterSignup(['sector' => 'coffee_shop', 'sales_mode' => 'dine_in']);

        $this->assertTrue($menu->json('features.customer_name'));
        $this->assertTrue($menu->json('features.open_bill'));
        $this->assertTrue($menu->json('features.modifiers'));
        $this->assertFalse($menu->json('features.tax_service'), 'pajak menunggu owner mengisi persen');
        $this->assertSame(['Kopi', 'Non Kopi', 'Makanan'], array_column($menu->json('categories'), 'name'));
        // Meja punya kolom sendiri (Dine-in) → kolom nama cukup "Nama pelanggan".
        $menu->assertJsonPath('customer_label_hint', 'Nama pelanggan');
        $menu->assertJsonPath('order_types', ['enabled' => true, 'default' => 'dine_in']);
    }

    public function test_food_signup_without_sales_mode_gets_order_types(): void
    {
        // Aplikasi baru tidak lagi menanyakan cara berjualan.
        $this->menuAfterSignup(['sector' => 'coffee_shop', 'sales_mode' => null])
            ->assertJsonPath('order_types', ['enabled' => true, 'default' => 'takeaway']);
        $this->menuAfterSignup(['sector' => 'restaurant', 'sales_mode' => null, 'email' => 'resto@contoh.id', 'device_id' => (string) Str::uuid()])
            ->assertJsonPath('order_types', ['enabled' => true, 'default' => 'dine_in']);
    }

    public function test_retail_has_no_variants_and_template_never_exceeds_plan(): void
    {
        $plan = Plan::where('code', 'gratis')->firstOrFail();
        DB::table('plan_features')->where('plan_id', $plan->id)->where('feature_key', 'split_payment')->delete();

        $menu = $this->menuAfterSignup(['sector' => 'retail', 'sales_mode' => 'mixed']);

        $this->assertFalse($menu->json('features.modifiers'));
        $this->assertFalse($menu->json('features.split_payment') ?? false, 'template tidak menyalakan fitur di luar paket');
        $this->assertSame(['Umum'], array_column($menu->json('categories'), 'name'));
    }

    public function test_owner_can_change_template_choices_later(): void
    {
        $res = $this->signup(['sector' => 'street_food', 'sales_mode' => 'takeaway'])->assertCreated();
        $owner = $this->api('POST', '/api/v1/auth/pin', $res->json('token'), ['user_id' => $res->json('owner_id'), 'pin' => '482915'])->json('token');

        $this->api('PUT', '/api/v1/settings/features', $owner, ['features' => ['customer_name' => true, 'open_bill' => true]])->assertOk();
        $this->api('GET', '/api/v1/menu', $owner)->assertJsonPath('features.open_bill', true);
    }

    // ─────────────── jenis usaha berkelompok & wilayah ───────────────

    public function test_options_list_grouped_sectors_sales_modes_and_regions(): void
    {
        $res = $this->api('GET', '/api/v1/signup/options')->assertOk();

        $this->assertSame(['food', 'retail', 'service', 'health', 'beauty', 'other'], array_column($res->json('sectors'), 'group'));
        $food = collect($res->json('sectors.0.items'))->keyBy('code');
        $this->assertTrue($food['coffee_shop']['asks_sales_mode']);
        $this->assertFalse(collect($res->json('sectors.2.items'))->firstWhere('code', 'laundry')['asks_sales_mode']);
        $this->assertCount(30, collect($res->json('sectors'))->flatMap(fn ($g) => $g['items']));
        $this->assertSame(['takeaway', 'dine_in', 'mixed'], array_column($res->json('sales_modes'), 'code'));

        $regions = $res->json('regions');
        $this->assertCount(38, $regions);
        $this->assertSame(514, collect($regions)->sum(fn ($p) => count($p['regencies'])));
    }

    public function test_other_sector_needs_description(): void
    {
        $this->signup(['sector' => 'other', 'sales_mode' => null])->assertJsonValidationErrors('sector_other');

        $res = $this->signup(['sector' => 'other', 'sector_other' => 'Rental PS', 'sales_mode' => null])->assertCreated();
        $tenant = Tenant::findOrFail($res->json('tenant.id'));
        $this->assertSame(['Rental PS', null], [$tenant->sector_other, $tenant->sales_mode]);
    }

    public function test_sales_mode_only_for_food_businesses(): void
    {
        $this->signup(['sector' => 'restaurant', 'sales_mode' => 'drive_thru'])->assertJsonValidationErrors('sales_mode');

        // Laundry: cara jualan diabaikan walau terkirim.
        $res = $this->signup(['sector' => 'laundry', 'sales_mode' => 'dine_in'])->assertCreated();
        $this->assertNull(Tenant::findOrFail($res->json('tenant.id'))->sales_mode);
    }

    public function test_region_must_exist_and_match_province(): void
    {
        $this->signup(['province_code' => '99'])->assertJsonValidationErrors('province_code');
        $this->signup(['regency_code' => '31.71'])->assertJsonValidationErrors('regency_code'); // Jakarta Pusat ≠ Sumut
        $this->signup(['province_code' => null, 'regency_code' => null])->assertJsonValidationErrors(['province_code', 'regency_code']);
    }

    public function test_laundry_template_names_customers_and_pays_later(): void
    {
        $menu = $this->menuAfterSignup(['sector' => 'laundry', 'sales_mode' => null]);

        $this->assertTrue($menu->json('features.customer_name'));
        $this->assertTrue($menu->json('features.open_bill'), 'bayar saat ambil cucian');
        $this->assertFalse($menu->json('features.modifiers'));
        $this->assertSame(['Kiloan', 'Satuan'], array_column($menu->json('categories'), 'name'));
        $menu->assertJsonPath('customer_label_hint', 'Nama pelanggan');
    }

    public function test_pharmacy_template_is_fast_checkout(): void
    {
        $menu = $this->menuAfterSignup(['sector' => 'pharmacy', 'sales_mode' => null]);

        $this->assertFalse($menu->json('features.customer_name'));
        $this->assertFalse($menu->json('features.open_bill'));
        $this->assertSame(['Obat Bebas', 'Vitamin & Suplemen', 'Alat Kesehatan'], array_column($menu->json('categories'), 'name'));
    }

    // ─────────────── verifikasi email sebelum daftar ───────────────

    public function test_email_code_is_sent_before_signup_and_marks_owner_verified(): void
    {
        Mail::fake();
        $this->api('POST', '/api/v1/signup/email-code', null, ['email' => 'Baru@Contoh.id', 'owner_name' => 'Wahyu'])->assertOk();
        $mail = Mail::sent(EmailCodeMail::class)->last();
        $this->assertTrue($mail->hasTo('baru@contoh.id'));
        $this->assertSame('Wahyu', $mail->name);

        $res = $this->signup(['email' => 'baru@contoh.id', 'email_code' => $mail->code])->assertCreated();

        $this->tenancy()->run($res->json('tenant.id'), function () {
            $this->assertNotNull(User::query()->sole()->email_verified_at, 'email sudah terbukti saat daftar');
        });
        Mail::assertSent(EmailCodeMail::class, 1); // tidak ada email verifikasi kedua setelah masuk (selain email selamat datang)
    }

    public function test_signup_rejects_missing_wrong_or_used_code(): void
    {
        $this->signup(['email_code' => null])->assertJsonValidationErrors('email_code');

        $this->signupCode('wahyu@contoh.id');
        $this->signup(['email_code' => '000000'])->assertUnprocessable()->assertJsonValidationErrors('email_code');
        $this->assertSame(0, Tenant::count());

        // Kode untuk email lain tidak berlaku.
        $this->signupCode('lain@contoh.id', '246802');
        $this->signup(['email_code' => '246802'])->assertJsonValidationErrors('email_code');

        $this->signup(['email_code' => '135790'])->assertCreated();
        $this->assertSame(1, Tenant::count());
    }

    public function test_email_code_endpoint_rules(): void
    {
        Mail::fake();
        $this->signup()->assertCreated();

        // Email sudah terdaftar → tidak dikirim.
        $this->api('POST', '/api/v1/signup/email-code', null, ['email' => 'wahyu@contoh.id'])
            ->assertJsonValidationErrors('email');
        $this->api('POST', '/api/v1/signup/email-code', null, ['email' => 'bukan email'])->assertJsonValidationErrors('email');

        $this->api('POST', '/api/v1/signup/email-code', null, ['email' => 'x@contoh.id'])->assertOk();
        $this->api('POST', '/api/v1/signup/email-code', null, ['email' => 'x@contoh.id'])->assertStatus(429);
        Mail::assertSent(EmailCodeMail::class, 1);
    }

    public function test_email_code_reports_mail_failure(): void
    {
        Mail::shouldReceive('to')->andThrow(new \RuntimeException('SMTP down'));

        $this->api('POST', '/api/v1/signup/email-code', null, ['email' => 'x@contoh.id'])->assertStatus(503);
    }
}
