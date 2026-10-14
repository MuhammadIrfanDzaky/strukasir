<?php

namespace App\Mail;

use App\Support\PlanCatalog;
use DateTimeInterface;

/** Kuitansi setelah paket lunas (via Mayar atau aktivasi admin). */
class PaymentReceiptMail extends BrandedMail
{
    public function __construct(
        public readonly string $ownerName,
        public readonly string $businessName,
        public readonly string $planName,
        public readonly string $period,
        public readonly int $baseAmount,
        public readonly int $discountPercent,
        public readonly ?string $discountReason,
        public readonly int $amount,
        public readonly DateTimeInterface $activeUntil,
        public readonly string $receiptNo,
        public readonly DateTimeInterface $paidAt,
    ) {}

    protected function message(): array
    {
        $months = PlanCatalog::months($this->period);
        $rows = [
            'No. kuitansi' => $this->receiptNo,
            'Tanggal' => self::date($this->paidAt),
            'Usaha' => $this->businessName,
            'Paket' => "{$this->planName} · {$months} bulan",
            'Harga' => self::rupiah($this->baseAmount),
        ];
        if ($this->discountPercent > 0) {
            $label = $this->discountReason === 'referral_reward' ? 'Kupon referral' : 'Diskon referral';
            $rows["{$label} {$this->discountPercent}%"] = '−'.self::rupiah($this->baseAmount - $this->amount);
        }
        $rows['Total dibayar'] = self::rupiah($this->amount);

        return [
            'subject' => "Pembayaran berhasil: Strukasir {$this->planName} {$months} bulan",
            'preheader' => 'Terima kasih! Paket '.$this->planName.' aktif sampai '.self::date($this->activeUntil).'.',
            'title' => 'Pembayaran berhasil',
            'greeting' => "Halo {$this->ownerName},",
            'intro' => ['Terima kasih, pembayaran Anda sudah kami terima.'],
            'box' => ['label' => 'Paket aktif sampai', 'value' => self::date($this->activeUntil), 'caption' => "Paket {$this->planName} untuk {$this->businessName}"],
            'rows' => $rows,
            'outro' => ['Simpan email ini sebagai bukti pembayaran. Perpanjangan bisa dilakukan kapan saja dari aplikasi: Upgrade paket → Perpanjang.'],
            'reason' => 'Anda menerima email ini karena ada pembayaran paket Strukasir untuk usaha Anda.',
        ];
    }
}
