<?php

namespace App\Enums;

/** Sektor usaha yang dipilih saat daftar. Nanti dipakai template modul per sektor. */
enum BusinessSector: string
{
    case CoffeeShop = 'coffee_shop';
    case Restaurant = 'restaurant';
    case StreetFood = 'street_food';
    case Bakery = 'bakery';
    case Retail = 'retail';
    case Service = 'service';
    case Other = 'other';
}
