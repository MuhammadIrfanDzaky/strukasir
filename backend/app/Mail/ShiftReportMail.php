<?php

namespace App\Mail;

/** Laporan tutup shift ke owner (isi sama dengan versi WhatsApp, tanda * dihapus). */
class ShiftReportMail extends BrandedMail
{
    public function __construct(
        public readonly string $subjectLine,
        public readonly string $body,
    ) {}

    protected function message(): array
    {
        // Baris pertama laporan ("Laporan shift <usaha>") jadi judul; sisanya isi (tidak dobel).
        $lines = explode("\n", trim(str_replace('*', '', $this->body)));
        $title = array_shift($lines);

        return [
            'subject' => $this->subjectLine,
            'preheader' => trim($lines[0] ?? '') ?: null,
            'title' => $title,
            'text' => trim(implode("\n", $lines)),
            'reason' => 'Dikirim otomatis saat shift ditutup. Matikan di Pengaturan → Fitur → Laporan harian.',
        ];
    }
}
