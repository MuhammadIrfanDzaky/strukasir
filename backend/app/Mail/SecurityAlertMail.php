<?php

namespace App\Mail;

use DateTimeInterface;
use Illuminate\Support\Carbon;

/** Peringatan keamanan ke owner: tablet baru didaftarkan / password diubah. */
class SecurityAlertMail extends BrandedMail
{
    public const DEVICE_ADDED = 'device_added';

    public const PASSWORD_CHANGED = 'password_changed';

    /** @param array<string, string> $details */
    public function __construct(
        public readonly string $ownerName,
        public readonly string $businessName,
        public readonly string $kind,
        public readonly DateTimeInterface $at,
        public readonly array $details = [],
    ) {}

    protected function message(): array
    {
        $device = $this->kind === self::DEVICE_ADDED;
        $time = self::date($this->at).' '.Carbon::instance($this->at)->timezone('Asia/Jakarta')->format('H:i').' WIB';

        return [
            'subject' => $device ? "Tablet baru terdaftar di {$this->businessName}" : 'Password akun Strukasir Anda diubah',
            'preheader' => $device ? 'Bukan Anda? Segera ganti password.' : 'Bukan Anda? Segera reset password.',
            'title' => $device ? 'Tablet baru terdaftar' : 'Password diubah',
            'greeting' => "Halo {$this->ownerName},",
            'intro' => [$device
                ? "Sebuah tablet baru saja didaftarkan ke {$this->businessName} memakai email & password owner."
                : "Password akun owner {$this->businessName} baru saja diubah."],
            'rows' => ['Waktu' => $time] + $this->details,
            'outro' => [$device
                ? 'Bila ini Anda, abaikan email ini. Bila bukan, segera ganti password (Masuk → Lupa password?) dan hubungi tim Strukasir untuk mencabut tablet itu.'
                : 'Bila ini Anda, abaikan email ini. Bila bukan, segera reset password dari aplikasi (Masuk → Lupa password?) dan hubungi tim Strukasir.'],
            'reason' => 'Email keamanan ini selalu dikirim ke owner dan tidak bisa dimatikan.',
        ];
    }
}
