<?php

namespace App\Enums;

/** Cara berjualan: hanya bawa pulang, makan di tempat (meja), atau keduanya. */
enum SalesMode: string
{
    case Takeaway = 'takeaway';
    case DineIn = 'dine_in';
    case Mixed = 'mixed';

    public function label(): string
    {
        return match ($this) {
            self::Takeaway => 'Bawa pulang saja',
            self::DineIn => 'Makan di tempat',
            self::Mixed => 'Keduanya',
        };
    }
}
