<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\TenantSetting;
use App\Support\Audit;
use App\Support\ReceiptLogo;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Pengaturan → Pembayaran QRIS (owner): gambar QRIS statis kedai + cetak di bill belum dibayar.
 * Tablet menerimanya lewat GET /menu (bagian `qris`), jadi tetap tampil saat internet putus.
 */
class QrisSettingsController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'image' => ['nullable', 'string', 'max:'.ReceiptLogo::QRIS_MAX_BASE64, function (string $attribute, mixed $value, Closure $fail) {
                if (is_string($value) && ($error = ReceiptLogo::validateQris($value)) !== null) {
                    $fail($error);
                }
            }],
            'remove_image' => ['sometimes', 'boolean'],
            'print_on_bill' => ['sometimes', 'boolean'],
        ]);

        $settings = TenantSetting::query()->firstOrFail();
        $before = self::summary($settings);
        if ($request->boolean('remove_image')) {
            $settings->qris_image = null;
        } elseif (! empty($data['image'])) {
            $settings->qris_image = $data['image'];
        }
        if (array_key_exists('print_on_bill', $data)) {
            $settings->qris_on_bill = (bool) $data['print_on_bill'];
        }
        $settings->save();
        Audit::record('settings.qris_updated', $settings, before: $before, after: self::summary($settings));

        return response()->json(['data' => self::present($settings) ?? ['image' => null, 'print_on_bill' => (bool) $settings->qris_on_bill]]);
    }

    /** Bagian `qris` di GET /menu; null bila kedai belum mengunggah QRIS. */
    public static function present(TenantSetting $s): ?array
    {
        return $s->qris_image === null ? null : ['image' => $s->qris_image, 'print_on_bill' => (bool) $s->qris_on_bill];
    }

    /** Audit tanpa menyalin gambar ke log. */
    private static function summary(TenantSetting $s): array
    {
        return ['image' => $s->qris_image === null ? null : sha1($s->qris_image), 'print_on_bill' => (bool) $s->qris_on_bill];
    }
}
