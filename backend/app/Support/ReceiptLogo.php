<?php

namespace App\Support;

/**
 * Validasi logo struk (SEC-27): hanya PNG, dicek dari isi (magic bytes + header gambar),
 * bukan dari nama/tipe yang dikirim klien. Batas ukuran & dimensi sesuai printer 58 mm.
 */
final class ReceiptLogo
{
    public const MAX_BYTES = 65536;

    /** base64 dari MAX_BYTES (dibulatkan ke kelipatan 4). */
    public const MAX_BASE64 = 87400;

    /** Lebar cetak printer thermal 58 mm = 384 titik. */
    public const MAX_WIDTH = 384;

    public const MAX_HEIGHT = 400;

    /** Gambar QRIS statis (sudah hitam-putih & diperkecil di tablet): cukup tajam untuk dipindai & dicetak. */
    public const QRIS_MAX_BYTES = 98304;

    public const QRIS_MAX_BASE64 = 131072;

    public const QRIS_MAX_HEIGHT = 640;

    private const PNG_MAGIC = "\x89PNG\r\n\x1a\n";

    /** Pesan error, atau null bila valid. */
    public static function validate(string $base64): ?string
    {
        return self::png($base64, 'Logo', self::MAX_BYTES, '64 KB', 16, self::MAX_WIDTH, self::MAX_HEIGHT);
    }

    /** Gambar QRIS: PNG, lebar ≤ 384 (kertas 58 mm), tidak terlalu kecil supaya tetap bisa dipindai. */
    public static function validateQris(string $base64): ?string
    {
        return self::png($base64, 'Gambar QRIS', self::QRIS_MAX_BYTES, '96 KB', 120, self::MAX_WIDTH, self::QRIS_MAX_HEIGHT);
    }

    private static function png(string $base64, string $label, int $maxBytes, string $maxLabel, int $min, int $maxW, int $maxH): ?string
    {
        $bytes = base64_decode($base64, true);
        if ($bytes === false || $bytes === '') {
            return "{$label} tidak valid.";
        }
        if (strlen($bytes) > $maxBytes) {
            return "{$label} terlalu besar (maks. {$maxLabel}).";
        }
        if (! str_starts_with($bytes, self::PNG_MAGIC)) {
            return "{$label} harus berupa gambar PNG.";
        }

        $info = @getimagesizefromstring($bytes);
        if ($info === false || $info[2] !== IMAGETYPE_PNG) {
            return "{$label} harus berupa gambar PNG.";
        }
        [$width, $height] = $info;
        if ($width < $min || $width > $maxW || $height < $min || $height > $maxH) {
            return "Ukuran {$label} harus {$min}–{$maxW} × {$min}–{$maxH} piksel.";
        }

        return null;
    }
}
