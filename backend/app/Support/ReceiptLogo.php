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

    private const PNG_MAGIC = "\x89PNG\r\n\x1a\n";

    /** Pesan error, atau null bila valid. */
    public static function validate(string $base64): ?string
    {
        $bytes = base64_decode($base64, true);
        if ($bytes === false || $bytes === '') {
            return 'Logo tidak valid.';
        }
        if (strlen($bytes) > self::MAX_BYTES) {
            return 'Logo terlalu besar (maks. 64 KB).';
        }
        if (! str_starts_with($bytes, self::PNG_MAGIC)) {
            return 'Logo harus berupa gambar PNG.';
        }

        $info = @getimagesizefromstring($bytes);
        if ($info === false || $info[2] !== IMAGETYPE_PNG) {
            return 'Logo harus berupa gambar PNG.';
        }
        [$width, $height] = $info;
        if ($width < 16 || $width > self::MAX_WIDTH || $height < 16 || $height > self::MAX_HEIGHT) {
            return 'Ukuran logo harus 16–'.self::MAX_WIDTH.' × 16–'.self::MAX_HEIGHT.' piksel.';
        }

        return null;
    }
}
