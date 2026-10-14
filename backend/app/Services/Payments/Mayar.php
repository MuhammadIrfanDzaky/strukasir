<?php

namespace App\Services\Payments;

use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * Klien Mayar API v2 (invoice). Kunci API hanya dari config (env), tidak pernah dicatat.
 * Webhook Mayar tidak bertanda tangan, jadi status lunas selalu diambil dari `GET /invoices/{id}`.
 * Dokumentasi: https://docs.mayar.id/api-reference-v2/invoice/create.md
 */
class Mayar
{
    public function enabled(): bool
    {
        return filled(config('services.mayar.api_key'));
    }

    private function baseUrl(): string
    {
        return config('services.mayar.sandbox') ? 'https://api.mayar.io/hl/v2' : 'https://api.mayar.id/hl/v2';
    }

    private function http()
    {
        return Http::withToken((string) config('services.mayar.api_key'))
            ->acceptJson()->asJson()->timeout(15)->retry(2, 500, throw: false);
    }

    /**
     * Buat invoice; pelanggan membayar di halaman Mayar (`link`), dibatasi ke QRIS bila diatur.
     *
     * @param  array{name: string, email: string, mobile: string}  $customer
     * @return array{id: string, link: string, expires_at: ?Carbon}
     */
    public function createInvoice(array $customer, int $amount, string $description, \DateTimeInterface $expiresAt, array $extra): array
    {
        $body = [
            ...$customer,
            'description' => $description,
            'expiredAt' => $expiresAt->format('Y-m-d\TH:i:s.v\Z'),
            'items' => [['quantity' => 1, 'rate' => $amount, 'description' => $description]],
            'extraData' => $extra,
        ];
        if (filled($method = config('services.mayar.payment_method'))) {
            $body['paymentMethod'] = $method;
        }
        $res = $this->http()->post($this->baseUrl().'/invoices/create', $body);
        $data = $res->json('data');
        if ($res->failed() || ! is_array($data) || empty($data['id']) || empty($data['link'])) {
            throw new RuntimeException('Mayar invoice gagal: '.$res->status().' '.($res->json('messages') ?? ''));
        }

        return ['id' => (string) $data['id'], 'link' => (string) $data['link'], 'expires_at' => self::time($data['expiredAt'] ?? null)];
    }

    /** `expiredAt` Mayar bisa berupa epoch milidetik (sesuai dokumentasi) atau teks tanggal ISO (sandbox). */
    public static function time(mixed $value): ?Carbon
    {
        return match (true) {
            is_int($value), is_float($value), is_string($value) && ctype_digit($value) => Carbon::createFromTimestampMs((int) $value),
            is_string($value) && $value !== '' => Carbon::parse($value)->utc(),
            default => null,
        };
    }

    /**
     * Status invoice langsung dari Mayar (sumber kebenaran).
     *
     * @return array{status: string, amount: int}|null null = tidak ditemukan / gagal dihubungi
     */
    public function invoice(string $id): ?array
    {
        try {
            $res = $this->http()->get($this->baseUrl().'/invoices/'.rawurlencode($id));
        } catch (RequestException) {
            return null;
        }
        $data = $res->json('data');
        if (! $res->successful() || ! is_array($data) || ! isset($data['status'])) {
            return null;
        }

        return ['status' => (string) $data['status'], 'amount' => (int) ($data['amount'] ?? -1)];
    }

    /** Status invoice Mayar → status tagihan kita. */
    public static function mapStatus(string $status): string
    {
        return match (strtolower($status)) {
            'paid', 'settled', 'success' => 'paid',
            'expired', 'closed' => 'expired',
            'failed', 'cancelled', 'canceled' => 'failed',
            default => 'pending',
        };
    }
}
