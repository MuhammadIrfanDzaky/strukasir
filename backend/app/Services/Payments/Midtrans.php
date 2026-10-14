<?php

namespace App\Services\Payments;

use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * Klien Midtrans Core API untuk QRIS dinamis. Kunci server hanya dari config (env), tidak pernah dicatat.
 * Dokumentasi: charge `POST /v2/charge` (payment_type=qris), status `GET /v2/{order_id}/status`,
 * tanda tangan notifikasi = SHA512(order_id + status_code + gross_amount + server_key).
 */
class Midtrans
{
    public function enabled(): bool
    {
        return filled(config('services.midtrans.server_key'));
    }

    private function baseUrl(): string
    {
        return config('services.midtrans.production') ? 'https://api.midtrans.com' : 'https://api.sandbox.midtrans.com';
    }

    private function http()
    {
        return Http::withBasicAuth((string) config('services.midtrans.server_key'), '')
            ->acceptJson()->asJson()->timeout(15)->retry(2, 500, throw: false);
    }

    /**
     * Buat QRIS untuk tagihan.
     *
     * @return array{transaction_id: ?string, qr_string: ?string, qr_url: ?string, expires_at: ?string}
     */
    public function chargeQris(string $orderId, int $amount, int $expiryMinutes): array
    {
        $res = $this->http()->post($this->baseUrl().'/v2/charge', [
            'payment_type' => 'qris',
            'transaction_details' => ['order_id' => $orderId, 'gross_amount' => $amount],
            'qris' => ['acquirer' => 'gopay'],
            'custom_expiry' => ['expiry_duration' => $expiryMinutes, 'unit' => 'minute'],
        ]);
        $body = $res->json() ?? [];
        if ($res->failed() || ! in_array((string) ($body['status_code'] ?? ''), ['200', '201'], true)) {
            throw new RuntimeException('Midtrans charge gagal: '.($body['status_code'] ?? $res->status()).' '.($body['status_message'] ?? ''));
        }
        $qrUrl = collect($body['actions'] ?? [])->firstWhere('name', 'generate-qr-code')['url'] ?? null;

        return [
            'transaction_id' => $body['transaction_id'] ?? null,
            'qr_string' => $body['qr_string'] ?? null,
            'qr_url' => $qrUrl,
            'expires_at' => $body['expiry_time'] ?? null,
        ];
    }

    /**
     * Status transaksi langsung dari Midtrans (sumber kebenaran; isi notifikasi tidak dipercaya begitu saja).
     *
     * @return array<string, mixed>|null null = transaksi tidak ditemukan / gagal dihubungi
     */
    public function status(string $orderId): ?array
    {
        try {
            $res = $this->http()->get($this->baseUrl().'/v2/'.rawurlencode($orderId).'/status');
        } catch (RequestException) {
            return null;
        }
        $body = $res->json();

        return $res->successful() && is_array($body) && isset($body['transaction_status']) ? $body : null;
    }

    /** @param array<string, mixed> $payload isi notifikasi HTTP */
    public function validSignature(array $payload): bool
    {
        $key = (string) config('services.midtrans.server_key');
        if ($key === '' || ! is_string($payload['signature_key'] ?? null)) {
            return false;
        }
        $expected = hash('sha512', ($payload['order_id'] ?? '').($payload['status_code'] ?? '').($payload['gross_amount'] ?? '').$key);

        return hash_equals($expected, $payload['signature_key']);
    }

    /** Status Midtrans → status tagihan kita. */
    public static function mapStatus(array $status): string
    {
        return match ($status['transaction_status'] ?? null) {
            'settlement' => 'paid',
            'capture' => ($status['fraud_status'] ?? 'accept') === 'accept' ? 'paid' : 'pending',
            'expire' => 'expired',
            'cancel', 'deny', 'failure' => 'failed',
            default => 'pending',
        };
    }
}
