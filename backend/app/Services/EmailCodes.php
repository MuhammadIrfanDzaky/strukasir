<?php

namespace App\Services;

use App\Mail\EmailCodeMail;
use App\Models\EmailCode;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Kode 6 digit lewat email untuk verifikasi email & reset password owner.
 * - Hanya hash yang disimpan; kode baru membatalkan kode lama dengan tujuan sama.
 * - Berlaku TTL_MINUTES, maks. MAX_ATTEMPTS salah, sekali pakai.
 * - Jeda RESEND_SECONDS antar pengiriman ke user yang sama (anti-spam kotak masuk).
 */
class EmailCodes
{
    public const VERIFY_EMAIL = 'verify_email';

    public const RESET_PASSWORD = 'reset_password';

    public const TTL_MINUTES = 15;

    public const MAX_ATTEMPTS = 5;

    public const RESEND_SECONDS = 60;

    /**
     * Buat & kirim kode baru. False bila masih dalam jeda kirim ulang atau email gagal terkirim
     * (gagal kirim dilaporkan ke log/Sentry, tidak membatalkan proses pemanggil).
     */
    public function send(User $user, string $purpose): bool
    {
        if (! $this->canSend($user, $purpose)) {
            return false;
        }

        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        EmailCode::query()->where('user_id', $user->id)->where('purpose', $purpose)->whereNull('used_at')
            ->update(['used_at' => now()]);

        $record = new EmailCode;
        $record->user_id = $user->id;
        $record->purpose = $purpose;
        $record->code_hash = Hash::make($code);
        $record->expires_at = now()->addMinutes(self::TTL_MINUTES);
        $record->save();

        try {
            Mail::to($user->email)->send(new EmailCodeMail($user->name, $purpose, $code));
        } catch (Throwable $e) {
            report($e);

            return false;
        }

        return true;
    }

    /** Belum ada kode dengan tujuan sama dalam RESEND_SECONDS terakhir. */
    public function canSend(User $user, string $purpose): bool
    {
        return $user->email !== null && ! EmailCode::query()
            ->where('user_id', $user->id)->where('purpose', $purpose)
            ->where('created_at', '>', now()->subSeconds(self::RESEND_SECONDS))
            ->exists();
    }

    /** Cek kode; benar → ditandai terpakai. Salah → percobaan bertambah. */
    public function consume(User $user, string $purpose, string $code): bool
    {
        $record = EmailCode::query()
            ->where('user_id', $user->id)->where('purpose', $purpose)
            ->whereNull('used_at')->where('expires_at', '>', now())
            ->latest('created_at')->lockForUpdate()->first();

        if ($record === null || $record->attempts >= self::MAX_ATTEMPTS) {
            Hash::make('timing-equalizer');

            return false;
        }

        if (! preg_match('/^\d{6}$/', $code) || ! Hash::check($code, $record->code_hash)) {
            $record->increment('attempts');

            return false;
        }

        $record->used_at = now();
        $record->save();

        return true;
    }
}
