<?php

namespace App\Enums;

/** Cara berjualan: hanya bawa pulang, makan di tempat (meja), atau keduanya. */
enum SalesMode: string
{
    case Takeaway = 'takeaway';
    case DineIn = 'dine_in';
    case Mixed = 'mixed';
}
