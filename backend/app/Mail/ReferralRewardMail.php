<?php

namespace App\Mail;

/** Pengajak mendapat kupon karena usaha ajakannya mulai berlangganan. */
class ReferralRewardMail extends BrandedMail
{
    public function __construct(
        public readonly string $ownerName,
        public readonly string $refereeName,
        public readonly int $percent,
        public readonly int $available,
    ) {}

    protected function message(): array
    {
        return [
            'subject' => "Anda dapat kupon diskon {$this->percent}% dari referral",
            'preheader' => "{$this->refereeName} mulai berlangganan Strukasir berkat ajakan Anda.",
            'title' => "Kupon diskon {$this->percent}% untuk Anda",
            'greeting' => "Halo {$this->ownerName},",
            'intro' => ["{$this->refereeName} baru saja berlangganan Strukasir dengan kode referral Anda. Terima kasih sudah mengajak!"],
            'box' => ['label' => 'Kupon tersedia', 'value' => "{$this->available} × diskon {$this->percent}%", 'caption' => 'Otomatis dipakai di pembayaran paket berikutnya (satu kupon per pembayaran).'],
            'outro' => ['Ajak usaha lain dari aplikasi: Upgrade paket → Ajak usaha lain → Bagikan lewat WhatsApp.'],
            'reason' => 'Anda menerima email ini karena kode referral usaha Anda dipakai di Strukasir.',
        ];
    }
}
