<?php

namespace App\Mail;

use App\Services\EmailCodes;

/** Kode 6 digit untuk verifikasi email / reset password. Tanpa tautan (mencegah phishing). */
class EmailCodeMail extends BrandedMail
{
    public function __construct(
        public readonly string $name,
        public readonly string $purpose,
        public readonly string $code,
    ) {}

    protected function message(): array
    {
        $reset = $this->purpose === EmailCodes::RESET_PASSWORD;

        return [
            'subject' => $reset ? "Kode reset password Strukasir: {$this->code}" : "Kode verifikasi email Strukasir: {$this->code}",
            'preheader' => "Kode Anda {$this->code}, berlaku ".EmailCodes::TTL_MINUTES.' menit.',
            'title' => $reset ? 'Reset password' : 'Verifikasi email Anda',
            'greeting' => "Halo {$this->name},",
            'intro' => [$reset
                ? 'Ada permintaan reset password akun owner Strukasir Anda. Masukkan kode ini di aplikasi:'
                : 'Masukkan kode ini di aplikasi Strukasir untuk memverifikasi email Anda:'],
            'code' => $this->code,
            'outro' => ['Kode berlaku '.EmailCodes::TTL_MINUTES.' menit dan hanya bisa dipakai sekali.'],
            'note' => 'Jangan berikan kode ini kepada siapa pun, termasuk yang mengaku dari Strukasir. '
                .'Bila Anda tidak memintanya, abaikan email ini. Akun Anda tetap aman.',
        ];
    }
}
