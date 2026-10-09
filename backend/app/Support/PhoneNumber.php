<?php

namespace App\Support;

/**
 * No HP pelanggan disimpan dalam satu format (+62…) supaya "0812…", "62812…" dan "+62 812-…"
 * dianggap nomor yang sama (unik per kedai, bisa dicari dengan cara ketik apa pun).
 */
final class PhoneNumber
{
    /** Null bila bukan nomor telepon yang masuk akal. */
    public static function normalize(?string $input): ?string
    {
        if ($input === null) {
            return null;
        }
        $plus = str_starts_with(ltrim($input), '+');
        $digits = preg_replace('/\D/', '', $input);

        if (! $plus) {
            $digits = match (true) {
                str_starts_with($digits, '62') => $digits,
                str_starts_with($digits, '0') => '62'.substr($digits, 1),
                str_starts_with($digits, '8') => '62'.$digits,
                default => $digits,
            };
        }

        return preg_match('/^\d{8,15}$/', $digits) ? '+'.$digits : null;
    }

    /**
     * Potongan angka untuk pencarian: "0812 34" → "81234" (cocok dengan +6281234…).
     * Null bila teks pencarian bukan angka.
     */
    public static function searchDigits(string $query): ?string
    {
        $q = trim($query);
        if (! preg_match('/^\+?[\d\s\-.]{3,}$/', $q)) {
            return null;
        }
        $digits = preg_replace('/\D/', '', $q);
        $digits = match (true) {
            str_starts_with($digits, '62') && strlen($digits) > 4 => substr($digits, 2),
            str_starts_with($digits, '0') => substr($digits, 1),
            default => $digits,
        };

        return $digits === '' ? null : $digits;
    }

    /** +6281234567890 → 0812****7890 (kasir cukup melihat 4 angka terakhir untuk memastikan orangnya). */
    public static function mask(?string $phone): ?string
    {
        if ($phone === null) {
            return null;
        }
        $local = str_starts_with($phone, '+62') ? '0'.substr($phone, 3) : $phone;

        return substr($local, 0, 4).str_repeat('*', max(0, strlen($local) - 8)).substr($local, -4);
    }
}
