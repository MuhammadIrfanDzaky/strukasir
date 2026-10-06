<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\ReceiptSettingsRequest;
use App\Models\TenantSetting;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;

/**
 * Pengaturan struk milik kedai (owner): nama, alamat, pesan penutup, logo.
 * Tablet menerimanya lewat GET /menu (bagian `receipt`) dan menyimpannya bersama cache menu,
 * sehingga struk tetap tercetak lengkap walau internet sedang putus.
 */
class ReceiptSettingsController extends Controller
{
    public function update(ReceiptSettingsRequest $request): JsonResponse
    {
        $settings = TenantSetting::query()->firstOrFail();
        $before = self::summary($settings);

        $settings->receipt_name = $request->string('name')->trim()->value();
        $settings->receipt_header = self::text($request->input('header'));
        $settings->receipt_footer = self::text($request->input('footer'));
        if ($request->boolean('remove_logo')) {
            $settings->receipt_logo = null;
        } elseif ($request->filled('logo')) {
            $settings->receipt_logo = $request->string('logo')->value();
        }
        $settings->save();

        Audit::record('settings.receipt_updated', $settings, before: $before, after: self::summary($settings));

        return response()->json(['data' => self::present($settings)]);
    }

    /** Bentuk yang dikirim ke tablet (juga dipakai MenuController). */
    public static function present(TenantSetting $s): array
    {
        return [
            'name' => $s->receipt_name,
            'header' => $s->receipt_header,
            'footer' => $s->receipt_footer,
            'logo' => $s->receipt_logo,
        ];
    }

    /** Untuk audit: isi teks + ada/tidaknya logo (tanpa menyalin gambar ke log). */
    private static function summary(TenantSetting $s): array
    {
        return [
            'name' => $s->receipt_name,
            'header' => $s->receipt_header,
            'footer' => $s->receipt_footer,
            'logo' => $s->receipt_logo === null ? null : sha1($s->receipt_logo),
        ];
    }

    private static function text(mixed $value): ?string
    {
        $value = is_string($value) ? trim(str_replace("\r\n", "\n", $value)) : '';

        return $value === '' ? null : $value;
    }
}
