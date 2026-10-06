<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use App\Support\TwoFactor;
use Illuminate\Support\Facades\DB;
use PragmaRX\Google2FA\Google2FA;
use Tests\TestCase;

/** SEC-19: 2FA owner (TOTP) saat mendaftarkan tablet. */
class TwoFactorTest extends TestCase
{
    private const SECRET = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP';

    private object $shop;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop();
    }

    private function enableTwoFactor(): void
    {
        $this->tenancy()->run($this->shop->tenant->id, function () {
            $owner = User::findOrFail($this->shop->owner->id);
            $owner->two_factor_secret = self::SECRET;
            $owner->two_factor_confirmed_at = now();
            $owner->save();
        });
    }

    private function owner(): User
    {
        return $this->tenancy()->run($this->shop->tenant->id, fn () => User::findOrFail($this->shop->owner->id));
    }

    private function register(?string $otp = null)
    {
        return $this->api('POST', '/api/v1/devices/register', null, array_filter([
            'email' => $this->shop->owner->email,
            'password' => self::OWNER_PASSWORD,
            'device_name' => 'Tablet Bar',
            'otp' => $otp,
        ]));
    }

    private function currentCode(): string
    {
        return (new Google2FA)->getCurrentOtp(self::SECRET);
    }

    public function test_registration_without_two_factor_needs_no_code(): void
    {
        $this->register()->assertCreated();
    }

    public function test_correct_password_without_code_asks_for_code_without_counting_a_failure(): void
    {
        $this->enableTwoFactor();

        $this->register()->assertUnprocessable()->assertJsonValidationErrors('otp');
        $this->assertSame(0, $this->owner()->failed_attempts);
    }

    public function test_wrong_code_is_rejected_counted_and_audited(): void
    {
        $this->enableTwoFactor();
        $wrong = $this->currentCode() === '000000' ? '111111' : '000000';

        $this->register($wrong)->assertUnprocessable()->assertJsonValidationErrors('otp');

        $this->assertSame(1, $this->owner()->failed_attempts);
        $this->assertTrue($this->tenancy()->run($this->shop->tenant->id,
            fn () => AuditLog::where('action', 'auth.otp_failed')->exists()));
    }

    public function test_correct_code_registers_and_cannot_be_replayed(): void
    {
        $this->enableTwoFactor();
        $code = $this->currentCode();

        $this->register($code)->assertCreated();
        $this->register($code)->assertUnprocessable()->assertJsonValidationErrors('otp');
    }

    public function test_wrong_password_never_reaches_the_code_step(): void
    {
        $this->enableTwoFactor();

        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => $this->shop->owner->email,
            'password' => 'salah-sekali',
            'device_name' => 'Tablet Bar',
            'otp' => $this->currentCode(),
        ])->assertUnprocessable()->assertJsonMissingValidationErrors('otp');
    }

    public function test_secret_is_encrypted_at_rest_and_hidden(): void
    {
        $this->enableTwoFactor();

        $raw = $this->tenancy()->bypass(fn () => DB::table('users')->where('id', $this->shop->owner->id)->value('two_factor_secret'));
        $this->assertNotSame(self::SECRET, $raw);
        $this->assertArrayNotHasKey('two_factor_secret', $this->owner()->toArray());
    }

    public function test_command_enables_after_a_valid_code_and_disables(): void
    {
        $this->app->instance(TwoFactor::class, new class extends TwoFactor
        {
            public function newSecret(): string
            {
                return 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP';
            }
        });

        $this->artisan('pos:owner-2fa', ['email' => $this->shop->owner->email])
            ->expectsQuestion('Kode 6 digit yang tampil di aplikasi', $this->currentCode() === '000000' ? '111111' : '000000')
            ->expectsQuestion('Kode 6 digit yang tampil di aplikasi', $this->currentCode())
            ->assertSuccessful();
        $this->assertTrue($this->owner()->hasTwoFactor());

        $this->artisan('pos:owner-2fa', ['email' => $this->shop->owner->email, '--disable' => true])->assertSuccessful();
        $this->assertFalse($this->owner()->hasTwoFactor());
    }
}
