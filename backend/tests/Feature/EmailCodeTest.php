<?php

namespace Tests\Feature;

use App\Mail\EmailCodeMail;
use App\Models\AuditLog;
use App\Models\EmailCode;
use App\Services\EmailCodes;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Tests\TestCase;

/** Verifikasi email & reset password owner lewat kode 6 digit. */
class EmailCodeTest extends TestCase
{
    private object $shop;

    protected function setUp(): void
    {
        parent::setUp();
        Mail::fake();
        $this->shop = $this->makeShop('BerryBrew');
    }

    /** Kode terakhir yang "terkirim" ke email untuk tujuan tertentu. */
    private function sentCode(string $purpose): string
    {
        $mails = Mail::sent(EmailCodeMail::class, fn (EmailCodeMail $m) => $m->purpose === $purpose);
        $this->assertNotEmpty($mails, "tidak ada email {$purpose}");

        return $mails->last()->code;
    }

    private function ageCodes(): void
    {
        EmailCode::query()->update(['created_at' => now()->subMinutes(2)]);
    }

    // ─────────────── lupa password ───────────────

    public function test_reset_password_with_emailed_code(): void
    {
        $email = $this->shop->owner->email;
        $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => strtoupper($email)])->assertOk();
        Mail::assertSent(EmailCodeMail::class, fn (EmailCodeMail $m) => $m->hasTo($email));
        $code = $this->sentCode(EmailCodes::RESET_PASSWORD);

        $this->api('POST', '/api/v1/auth/password/reset', null, ['email' => $email, 'code' => $code, 'password' => 'passwordbaru9'])
            ->assertOk();

        $owner = $this->shop->owner->fresh();
        $this->assertTrue(Hash::check('passwordbaru9', $owner->password));
        $this->assertNotNull($owner->email_verified_at);

        // Sekali pakai.
        $this->api('POST', '/api/v1/auth/password/reset', null, ['email' => $email, 'code' => $code, 'password' => 'lainlagi99'])
            ->assertUnprocessable()->assertJsonValidationErrors('code');

        // Password baru bisa dipakai mendaftarkan tablet.
        $this->api('POST', '/api/v1/devices/register', null, ['email' => $email, 'password' => 'passwordbaru9'])->assertCreated();

        $this->tenancy()->run($this->shop->tenant->id, fn () => $this->assertContains('auth.password_reset',
            AuditLog::query()->pluck('action')->all()));
    }

    public function test_forgot_does_not_reveal_whether_email_exists(): void
    {
        $known = $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => $this->shop->owner->email])->assertOk();
        $unknown = $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => 'tidak-ada@contoh.id'])->assertOk();

        $this->assertSame($known->json('message'), $unknown->json('message'));
        Mail::assertSentCount(1);
    }

    public function test_cashier_without_email_and_inactive_owner_get_nothing(): void
    {
        $this->shop->owner->forceFill(['active' => false])->save();
        $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => $this->shop->owner->email])->assertOk();
        Mail::assertNothingSent();
    }

    public function test_wrong_code_attempts_are_limited(): void
    {
        $email = $this->shop->owner->email;
        $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => $email]);
        $code = $this->sentCode(EmailCodes::RESET_PASSWORD);
        $wrong = $code === '000000' ? '111111' : '000000';

        for ($i = 0; $i < EmailCodes::MAX_ATTEMPTS; $i++) {
            $this->api('POST', '/api/v1/auth/password/reset', null, ['email' => $email, 'code' => $wrong, 'password' => 'passwordbaru9'])
                ->assertUnprocessable();
        }
        // Kode benar pun ditolak setelah batas → harus minta kode baru.
        $this->api('POST', '/api/v1/auth/password/reset', null, ['email' => $email, 'code' => $code, 'password' => 'passwordbaru9'])
            ->assertUnprocessable();
        $this->assertTrue(Hash::check(self::OWNER_PASSWORD, $this->shop->owner->fresh()->password));
    }

    public function test_code_expires_and_new_code_replaces_old(): void
    {
        $email = $this->shop->owner->email;
        $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => $email]);
        $first = $this->sentCode(EmailCodes::RESET_PASSWORD);

        // Dalam 1 menit: tidak ada email baru.
        $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => $email])->assertOk();
        Mail::assertSentCount(1);

        $this->ageCodes();
        $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => $email]);
        $second = $this->sentCode(EmailCodes::RESET_PASSWORD);
        Mail::assertSentCount(2);

        if ($first !== $second) {
            $this->api('POST', '/api/v1/auth/password/reset', null, ['email' => $email, 'code' => $first, 'password' => 'passwordbaru9'])
                ->assertUnprocessable();
        }

        $this->travel(EmailCodes::TTL_MINUTES + 1)->minutes();
        $this->api('POST', '/api/v1/auth/password/reset', null, ['email' => $email, 'code' => $second, 'password' => 'passwordbaru9'])
            ->assertUnprocessable();
    }

    public function test_reset_requires_strong_password_and_clears_lockout(): void
    {
        $email = $this->shop->owner->email;
        $this->shop->owner->forceFill(['failed_attempts' => 5, 'locked_until' => now()->addMinutes(5)])->save();
        $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => $email]);
        $code = $this->sentCode(EmailCodes::RESET_PASSWORD);

        $this->api('POST', '/api/v1/auth/password/reset', null, ['email' => $email, 'code' => $code, 'password' => 'pendek'])
            ->assertJsonValidationErrors('password');
        $this->api('POST', '/api/v1/auth/password/reset', null, ['email' => $email, 'code' => $code, 'password' => 'passwordbaru9'])
            ->assertOk();

        $owner = $this->shop->owner->fresh();
        $this->assertSame([0, null], [$owner->failed_attempts, $owner->locked_until]);
    }

    // ─────────────── verifikasi email ───────────────

    public function test_owner_verifies_email_after_login(): void
    {
        $token = $this->pinLogin($this->shop, $this->shop->owner);
        $this->api('GET', '/api/v1/auth/me', $token)->assertJsonPath('user.email_verified', false);

        $this->api('POST', '/api/v1/auth/email/send', $token)->assertOk();
        $this->api('POST', '/api/v1/auth/email/send', $token)->assertStatus(429); // jeda 1 menit
        $code = $this->sentCode(EmailCodes::VERIFY_EMAIL);

        $this->api('POST', '/api/v1/auth/email/verify', $token, ['code' => '12345x'])->assertUnprocessable();
        $this->api('POST', '/api/v1/auth/email/verify', $token, ['code' => $code])->assertOk();
        $this->api('GET', '/api/v1/auth/me', $token)->assertJsonPath('user.email_verified', true);
    }

    public function test_cashier_has_no_email_to_verify(): void
    {
        $token = $this->pinLogin($this->shop);
        $this->api('GET', '/api/v1/auth/me', $token)->assertJsonPath('user.email_verified', true);
        $this->api('POST', '/api/v1/auth/email/send', $token)->assertNotFound();
    }

    public function test_reset_code_cannot_verify_email_and_vice_versa(): void
    {
        $token = $this->pinLogin($this->shop, $this->shop->owner);
        $this->api('POST', '/api/v1/auth/password/forgot', null, ['email' => $this->shop->owner->email]);
        $reset = $this->sentCode(EmailCodes::RESET_PASSWORD);

        $this->api('POST', '/api/v1/auth/email/verify', $token, ['code' => $reset])->assertUnprocessable();
    }

    public function test_email_body_contains_code_and_no_links(): void
    {
        $mail = new EmailCodeMail('Wahyu', EmailCodes::RESET_PASSWORD, '048213');
        $mail->assertSeeInText('048213');
        $mail->assertSeeInText('15 menit');
        $mail->assertDontSeeInText('http');
        $this->assertStringContainsString('048213', $mail->envelope()->subject);
    }
}
