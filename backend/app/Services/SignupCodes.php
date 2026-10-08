<?php

namespace App\Services;

use App\Mail\EmailCodeMail;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Throwable;

/**
 * Kode 6 digit untuk memverifikasi email calon owner sebelum usaha dibuat. Aturan sama dengan
 * EmailCodes: hash saja, berlaku TTL_MINUTES, maks. MAX_ATTEMPTS salah, sekali pakai, jeda kirim.
 */
class SignupCodes
{
    public const SENT = 'sent';

    public const WAIT = 'wait';

    public const FAILED = 'failed';

    /** @return self::SENT|self::WAIT|self::FAILED */
    public function send(string $email, string $name = ''): string
    {
        $email = strtolower(trim($email));
        $recent = DB::table('signup_codes')->where('email', $email)
            ->where('created_at', '>', now()->subSeconds(EmailCodes::RESEND_SECONDS))->exists();
        if ($recent) {
            return self::WAIT;
        }

        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
        DB::table('signup_codes')->where('email', $email)->whereNull('used_at')->update(['used_at' => now()]);
        DB::table('signup_codes')->insert([
            'id' => (string) Str::uuid7(),
            'email' => $email,
            'code_hash' => Hash::make($code),
            'expires_at' => now()->addMinutes(EmailCodes::TTL_MINUTES),
            'created_at' => now(),
        ]);

        try {
            Mail::to($email)->send(new EmailCodeMail(trim($name) !== '' ? trim($name) : 'Calon pengguna Strukasir',
                EmailCodes::VERIFY_EMAIL, $code));
        } catch (Throwable $e) {
            report($e);

            return self::FAILED;
        }

        return self::SENT;
    }

    /** Benar → ditandai terpakai. Salah → percobaan bertambah. Dipanggil di dalam transaksi. */
    public function consume(string $email, string $code): bool
    {
        $record = DB::table('signup_codes')
            ->where('email', strtolower(trim($email)))->whereNull('used_at')->where('expires_at', '>', now())
            ->orderByDesc('created_at')->lockForUpdate()->first();

        if ($record === null || $record->attempts >= EmailCodes::MAX_ATTEMPTS) {
            Hash::make('timing-equalizer');

            return false;
        }

        if (! preg_match('/^\d{6}$/', $code) || ! Hash::check($code, $record->code_hash)) {
            DB::table('signup_codes')->where('id', $record->id)->increment('attempts');

            return false;
        }

        DB::table('signup_codes')->where('id', $record->id)->update(['used_at' => now()]);

        return true;
    }
}
