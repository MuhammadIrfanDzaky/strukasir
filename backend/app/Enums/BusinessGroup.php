<?php

namespace App\Enums;

/** Kelompok jenis usaha: judul di daftar pilihan saat daftar & dasar template fitur awal. */
enum BusinessGroup: string
{
    case Food = 'food';
    case Retail = 'retail';
    case Service = 'service';
    case Health = 'health';
    case Beauty = 'beauty';
    case Other = 'other';

    public function label(): string
    {
        return match ($this) {
            self::Food => 'Makanan & minuman',
            self::Retail => 'Retail',
            self::Service => 'Jasa & pelayanan',
            self::Health => 'Kesehatan',
            self::Beauty => 'Perawatan diri & kecantikan',
            self::Other => 'Lainnya',
        };
    }
}
