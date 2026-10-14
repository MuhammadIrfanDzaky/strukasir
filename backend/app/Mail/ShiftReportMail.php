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
        return [
            'subject' => $this->subjectLine,
            'preheader' => strtok(str_replace('*', '', $this->body), "\n") ?: null,
            'title' => 'Laporan tutup shift',
            'text' => str_replace('*', '', $this->body),
            'reason' => 'Dikirim otomatis saat shift ditutup. Matikan di Pengaturan → Fitur → Laporan harian.',
        ];
    }
}
