<?php

namespace App\Mail;

use App\Services\EmailCodes;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

/** Email berisi kode 6 digit (teks biasa: terbaca di semua aplikasi email, tanpa gambar/link). */
class EmailCodeMail extends Mailable
{
    public function __construct(
        public readonly string $name,
        public readonly string $purpose,
        public readonly string $code,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: $this->purpose === EmailCodes::RESET_PASSWORD
            ? "Kode reset password Strukasir: {$this->code}"
            : "Kode verifikasi email Strukasir: {$this->code}");
    }

    public function content(): Content
    {
        return new Content(text: 'mail.email-code', with: ['minutes' => EmailCodes::TTL_MINUTES]);
    }
}
