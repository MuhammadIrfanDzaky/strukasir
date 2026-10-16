<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

class ProfileTest extends TestCase
{
    private object $shop;

    private string $owner;

    private string $cashier;

    protected function setUp(): void
    {
        parent::setUp();
        Mail::fake();
        $this->shop = $this->makeShop('BerryBrew');
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->cashier = $this->pinLogin($this->shop);
    }

    private function fresh(User $u): User
    {
        return $this->tenancy()->run($this->shop->tenant->id, fn () => User::query()->findOrFail($u->id));
    }

    public function test_ubah_nama_sendiri_dan_nama_harus_unik(): void
    {
        $this->api('PUT', '/api/v1/auth/profile', $this->cashier, ['name' => '  Budi   Santoso '])
            ->assertOk()->assertJsonPath('data.name', 'Budi Santoso')->assertJsonPath('data.email', null);
        $this->api('PUT', '/api/v1/auth/profile', $this->cashier, ['name' => 'Owner'])
            ->assertUnprocessable()->assertJsonValidationErrors('name');
        // Kasir tidak bisa memberi dirinya email.
        $this->api('PUT', '/api/v1/auth/profile', $this->cashier, ['name' => 'Budi', 'email' => 'x@contoh.id'])->assertOk();
        $this->assertNull($this->fresh($this->shop->cashier)->email);
    }

    public function test_owner_ganti_email_butuh_password_dan_verifikasi_ulang(): void
    {
        $email = $this->fresh($this->shop->owner)->email;
        $this->api('PUT', '/api/v1/auth/profile', $this->owner, ['name' => 'Owner', 'email' => $email])->assertOk();
        $this->api('PUT', '/api/v1/auth/profile', $this->owner, ['name' => 'Owner', 'email' => 'baru@contoh.id', 'current_password' => 'salah'])
            ->assertUnprocessable()->assertJsonValidationErrors('current_password');

        // Email milik usaha lain (beda tenant, tersembunyi oleh RLS) tetap ditolak.
        $other = $this->makeShop('Lain');
        $taken = $this->tenancy()->run($other->tenant->id, fn () => User::query()->findOrFail($other->owner->id)->email);
        $this->api('PUT', '/api/v1/auth/profile', $this->owner, ['name' => 'Owner', 'email' => $taken, 'current_password' => self::OWNER_PASSWORD])
            ->assertUnprocessable()->assertJsonValidationErrors('email');

        $this->api('PUT', '/api/v1/auth/profile', $this->owner, ['name' => 'Owner', 'email' => ' Baru@Contoh.id ', 'current_password' => self::OWNER_PASSWORD])
            ->assertOk()->assertJsonPath('data.email', 'baru@contoh.id')->assertJsonPath('data.email_verified', false);
    }

    public function test_ganti_pin_butuh_pin_lama(): void
    {
        $this->api('PUT', '/api/v1/auth/profile/pin', $this->cashier, ['current_pin' => '000000', 'pin' => '482915'])
            ->assertUnprocessable()->assertJsonValidationErrors('current_pin');
        $this->api('PUT', '/api/v1/auth/profile/pin', $this->cashier, ['current_pin' => self::PIN, 'pin' => '123456'])
            ->assertUnprocessable()->assertJsonValidationErrors('pin');
        $this->api('PUT', '/api/v1/auth/profile/pin', $this->cashier, ['current_pin' => self::PIN, 'pin' => '482915'])->assertOk();
        $this->assertTrue(Hash::check('482915', $this->fresh($this->shop->cashier)->pin_hash));
        $this->api('GET', '/api/v1/auth/me', $this->cashier)->assertOk(); // sesi ini tetap
    }

    public function test_ganti_password_hanya_owner_dan_butuh_password_lama(): void
    {
        $new = ['current_password' => self::OWNER_PASSWORD, 'password' => 'rahasia-baru-9', 'password_confirmation' => 'rahasia-baru-9'];
        $this->api('PUT', '/api/v1/auth/profile/password', $this->cashier, $new)->assertForbidden();
        $this->api('PUT', '/api/v1/auth/profile/password', $this->owner, [...$new, 'current_password' => 'salah'])
            ->assertUnprocessable()->assertJsonValidationErrors('current_password');
        $this->api('PUT', '/api/v1/auth/profile/password', $this->owner, [...$new, 'password_confirmation' => 'lain'])
            ->assertUnprocessable()->assertJsonValidationErrors('password');
        $this->api('PUT', '/api/v1/auth/profile/password', $this->owner, $new)->assertOk();
        $this->assertTrue(Hash::check('rahasia-baru-9', $this->fresh($this->shop->owner)->password));
    }
}
