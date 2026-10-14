<?php

namespace App\Mail;

use DateTimeInterface;

/** Sambutan setelah daftar usaha: paket & masa coba, langkah awal, kode referral. */
class WelcomeMail extends BrandedMail
{
    public function __construct(
        public readonly string $ownerName,
        public readonly string $businessName,
        public readonly string $planName,
        public readonly bool $free,
        public readonly ?DateTimeInterface $endsAt,
        public readonly ?string $referralCode,
    ) {}

    protected function message(): array
    {
        $until = $this->endsAt ? self::date($this->endsAt) : null;

        return [
            'subject' => "Selamat datang di Strukasir, {$this->businessName}!",
            'preheader' => 'Tiga langkah supaya kasir siap dipakai hari ini.',
            'title' => 'Selamat datang di Strukasir',
            'greeting' => "Halo {$this->ownerName},",
            'intro' => ["Usaha {$this->businessName} sudah terdaftar dan tablet Anda siap dipakai."],
            'box' => $this->free
                ? ['label' => 'Masa coba gratis', 'value' => "sampai {$until}", 'caption' => 'Pilih paket kapan saja dari menu Upgrade paket di aplikasi.']
                : ['label' => "Paket {$this->planName}", 'value' => "bisa dipakai sampai {$until}", 'caption' => 'Selesaikan pembayaran dari menu Upgrade paket supaya paket aktif penuh.'],
            'steps' => [
                'Tambah produk & harga di Kelola Menu (bisa impor dari file CSV).',
                'Sambungkan printer di Pengaturan → Printer struk.',
                'Tambah kasir di Pengaturan → Pegawai, lalu buka shift dan mulai berjualan.',
            ],
            'outro' => $this->referralCode
                ? ["Kode referral Anda: {$this->referralCode}. Usaha yang daftar dengan kode ini dapat coba 14 hari & diskon 25%, dan Anda dapat diskon 50% untuk setiap usaha yang berlangganan."]
                : [],
            'note' => 'Butuh bantuan? Balas email ini, tim Strukasir akan membantu.',
            'reason' => 'Anda menerima email ini karena baru mendaftarkan usaha di Strukasir.',
        ];
    }
}
