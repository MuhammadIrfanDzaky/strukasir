<?php

namespace App\Support;

/**
 * Daftar provinsi & kota/kabupaten Indonesia (kode Kemendagri, 38 provinsi / 514 kab-kota),
 * dari resources/data/regions.json (sumber: wilayah.id). Dipakai pilihan alamat saat daftar.
 */
final class Regions
{
    /** @var list<array{code: string, name: string, regencies: list<array{code: string, name: string}>}>|null */
    private static ?array $data = null;

    /** @return list<array{code: string, name: string, regencies: list<array{code: string, name: string}>}> */
    public static function all(): array
    {
        return self::$data ??= json_decode(
            (string) file_get_contents(resource_path('data/regions.json')), true, flags: JSON_THROW_ON_ERROR);
    }

    public static function provinceExists(string $code): bool
    {
        return in_array($code, array_column(self::all(), 'code'), true);
    }

    /** Kota/kabupaten ada DAN berada di provinsi tersebut (kode kab-kota diawali kode provinsi). */
    public static function regencyIn(string $provinceCode, string $regencyCode): bool
    {
        foreach (self::all() as $province) {
            if ($province['code'] === $provinceCode) {
                return in_array($regencyCode, array_column($province['regencies'], 'code'), true);
            }
        }

        return false;
    }
}
