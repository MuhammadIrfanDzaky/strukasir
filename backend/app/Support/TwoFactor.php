<?php

namespace App\Support;

use App\Models\User;
use PragmaRX\Google2FA\Google2FA;

/**
 * 2FA berbasis TOTP (Google Authenticator, Aegis, dll.) untuk owner (SEC-19).
 * Kode berlaku ±30 detik (toleransi 1 langkah) dan tiap langkah waktu hanya bisa dipakai sekali.
 */
class TwoFactor
{
    public function __construct(private readonly Google2FA $engine = new Google2FA) {}

    /** Rahasia baru 32 karakter base32 (160 bit, sesuai RFC 4226). */
    public function newSecret(): string
    {
        return $this->engine->generateSecretKey(32);
    }

    /** URI untuk QR / impor manual di aplikasi authenticator. */
    public function otpauthUri(User $user, string $secret): string
    {
        return $this->engine->getQRCodeUrl('Strukasir', (string) $user->email, $secret);
    }

    /**
     * Cek kode terhadap rahasia owner. Menyimpan langkah waktu yang terpakai sehingga kode yang
     * sama (atau yang lebih lama) ditolak bila dikirim ulang.
     */
    public function verify(User $user, string $code, ?string $secret = null): bool
    {
        $secret ??= $user->two_factor_secret;
        if ($secret === null || ! preg_match('/^\d{6}$/', $code)) {
            return false;
        }

        // Selalu kirim angka (bukan null) agar library mengembalikan langkah waktu yang cocok.
        $step = $this->engine->verifyKeyNewer($secret, $code, $user->two_factor_last_step ?? 0, 1);
        if (! is_int($step)) {
            return false;
        }

        $user->two_factor_last_step = $step;
        $user->save();

        return true;
    }
}
