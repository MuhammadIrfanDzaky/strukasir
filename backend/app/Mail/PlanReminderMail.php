<?php

namespace App\Mail;

use DateTimeInterface;

/** Pengingat masa coba / paket: H-3, H-1, dan saat sudah habis. */
class PlanReminderMail extends BrandedMail
{
    public function __construct(
        public readonly string $ownerName,
        public readonly string $businessName,
        public readonly string $planName,
        public readonly string $status, // trial | awaiting_payment | active
        public readonly DateTimeInterface $endsAt,
        public readonly int $daysLeft, // 0 = sudah habis
    ) {}

    protected function message(): array
    {
        $what = match ($this->status) {
            'trial' => 'Masa coba gratis',
            'awaiting_payment' => "Batas pembayaran paket {$this->planName}",
            default => "Paket {$this->planName}",
        };
        $date = self::date($this->endsAt);

        if ($this->daysLeft <= 0) {
            return [
                'subject' => "{$what} Strukasir sudah berakhir",
                'preheader' => 'Data Anda aman. Aktifkan paket untuk lanjut berjualan.',
                'title' => "{$what} sudah berakhir",
                'greeting' => "Halo {$this->ownerName},",
                'intro' => ["{$what} untuk {$this->businessName} berakhir {$date}. Kasir tidak bisa membuat order baru atau membuka shift sampai paket diaktifkan."],
                'box' => ['label' => 'Data Anda aman', 'value' => 'Menu, pelanggan & laporan tetap tersimpan', 'caption' => 'Semua kembali seperti semula begitu paket aktif.'],
                'steps' => ['Buka aplikasi Strukasir di tablet.', 'Ketuk kotak paket di bawah menu samping.', 'Pilih paket & periode, lalu bayar dengan QRIS.'],
                'reason' => 'Pemberitahuan akun untuk owner usaha di Strukasir.',
            ];
        }

        $when = $this->daysLeft === 1 ? 'besok' : "{$this->daysLeft} hari lagi";

        // Gaya pemberitahuan akun (bukan promosi) supaya Gmail menaruhnya di tab Utama.
        return [
            'subject' => "{$what} Strukasir Anda berakhir {$date}",
            'preheader' => "{$what} untuk {$this->businessName} berakhir {$when}.",
            'title' => "{$what} berakhir {$when}",
            'greeting' => "Halo {$this->ownerName},",
            'intro' => ["{$what} untuk {$this->businessName} berakhir {$date}. Setelah tanggal itu kasir tidak bisa membuat order baru sampai paket diaktifkan."],
            'steps' => ['Buka aplikasi Strukasir di tablet.', 'Ketuk kotak paket di bawah menu samping.', 'Pilih paket & periode, lalu bayar dengan QRIS.'],
            'reason' => 'Pemberitahuan akun untuk owner usaha di Strukasir.',
        ];
    }
}
