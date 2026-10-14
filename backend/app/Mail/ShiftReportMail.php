<?php

namespace App\Mail;

/**
 * Laporan tutup shift ke owner. Dengan data terstruktur: angka besar + grafik batang (tabel HTML, terbaca di
 * Gmail/Outlook). Versi teks = isi WhatsApp (tanda * dihapus).
 */
class ShiftReportMail extends BrandedMail
{
    /** @param array<string, mixed>|null $data hasil ShiftReportService::data() */
    public function __construct(
        public readonly string $subjectLine,
        public readonly string $body,
        public readonly ?array $data = null,
    ) {}

    protected function message(): array
    {
        $lines = explode("\n", trim(str_replace('*', '', $this->body)));
        $title = array_shift($lines);
        $d = $this->data;

        return [
            'subject' => $this->subjectLine,
            'preheader' => $d !== null
                ? 'Penjualan '.self::rupiah($d['sales'])." · {$d['orders']} transaksi"
                : (trim($lines[0] ?? '') ?: null),
            'title' => $title,
            // Tanpa data (pemanggil lama): tampilkan teksnya saja.
            'text' => $d === null ? trim(implode("\n", $lines)) : null,
            'partial' => $d === null ? null : ['view' => 'mail.partials.shift-report', 'data' => ['d' => $d]],
            'text_fallback' => trim(implode("\n", $lines)),
            'reason' => 'Dikirim otomatis saat shift ditutup. Matikan di Pengaturan → Fitur → Laporan harian.',
        ];
    }
}
