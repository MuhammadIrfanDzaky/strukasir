<?php

namespace App\Mail;

use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Support\Carbon;

/**
 * Dasar semua email Strukasir: satu template HTML bermerek (tenang, tanpa gambar eksternal) + versi teks.
 * Turunan cukup mengisi `message()`:
 *  - subject, preheader (cuplikan di daftar email), title, greeting
 *  - intro / outro: paragraf; text: blok teks berbaris (laporan); code: kode besar; rows: [label => nilai]; box: kotak sorotan (judul + isi)
 *  - steps: daftar langkah bernomor; button: [label, url]; note: catatan kecil abu-abu; reason: alasan email dikirim
 */
abstract class BrandedMail extends Mailable
{
    /** @return array<string, mixed> */
    abstract protected function message(): array;

    public function envelope(): Envelope
    {
        return new Envelope(subject: $this->message()['subject']);
    }

    public function content(): Content
    {
        $m = $this->message() + [
            'preheader' => null, 'title' => null, 'greeting' => null, 'intro' => [], 'text' => null, 'code' => null, 'rows' => [],
            'box' => null, 'steps' => [], 'button' => null, 'outro' => [], 'note' => null, 'reason' => null,
        ];

        return new Content(view: 'mail.branded', text: 'mail.branded-text', with: ['m' => $m]);
    }

    protected static function rupiah(int $amount): string
    {
        return 'Rp'.number_format($amount, 0, ',', '.');
    }

    protected static function date(\DateTimeInterface $date): string
    {
        $months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
        $d = Carbon::instance($date)->timezone('Asia/Jakarta');

        return $d->day.' '.$months[$d->month - 1].' '.$d->year;
    }
}
