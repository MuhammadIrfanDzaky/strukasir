<?php

namespace App\Enums;

/**
 * Jenis usaha yang dipilih saat daftar, dikelompokkan per BusinessGroup (urutan case = urutan tampil).
 * Kode lama (coffee_shop, restaurant, street_food, bakery, retail, service, other) tetap dipakai
 * supaya data kedai yang sudah daftar tidak perlu diubah.
 */
enum BusinessSector: string
{
    // Makanan & minuman
    case CoffeeShop = 'coffee_shop';
    case Restaurant = 'restaurant';
    case StreetFood = 'street_food';
    case Catering = 'catering';
    case Bakery = 'bakery';
    case Beverage = 'beverage';
    case FrozenFood = 'frozen_food';

    // Retail
    case Retail = 'retail';
    case Minimarket = 'minimarket';
    case Fashion = 'fashion';
    case Gadget = 'gadget';
    case Electronics = 'electronics';
    case BuildingSupplies = 'building_supplies';
    case PetShop = 'pet_shop';
    case Florist = 'florist';

    // Jasa
    case Laundry = 'laundry';
    case Workshop = 'workshop';
    case Printing = 'printing';
    case Repair = 'repair';
    case PetSalon = 'pet_salon';
    case Service = 'service';

    // Kesehatan
    case Pharmacy = 'pharmacy';
    case Optic = 'optic';
    case Clinic = 'clinic';
    case Fitness = 'fitness';

    // Kecantikan
    case Salon = 'salon';
    case Spa = 'spa';
    case Skincare = 'skincare';
    case NailArt = 'nail_art';

    case Other = 'other';

    public function group(): BusinessGroup
    {
        return match ($this) {
            self::CoffeeShop, self::Restaurant, self::StreetFood, self::Catering, self::Bakery,
            self::Beverage, self::FrozenFood => BusinessGroup::Food,
            self::Retail, self::Minimarket, self::Fashion, self::Gadget, self::Electronics,
            self::BuildingSupplies, self::PetShop, self::Florist => BusinessGroup::Retail,
            self::Laundry, self::Workshop, self::Printing, self::Repair, self::PetSalon,
            self::Service => BusinessGroup::Service,
            self::Pharmacy, self::Optic, self::Clinic, self::Fitness => BusinessGroup::Health,
            self::Salon, self::Spa, self::Skincare, self::NailArt => BusinessGroup::Beauty,
            self::Other => BusinessGroup::Other,
        };
    }

    public function label(): string
    {
        return match ($this) {
            self::CoffeeShop => 'Kafe & coffee shop',
            self::Restaurant => 'Restoran & rumah makan',
            self::StreetFood => 'Warung & gerobak makanan',
            self::Catering => 'Katering',
            self::Bakery => 'Roti, kue & camilan',
            self::Beverage => 'Minuman (es teh, jus, boba)',
            self::FrozenFood => 'Pangan segar & frozen food',
            self::Retail => 'Toko kelontong & retail',
            self::Minimarket => 'Minimarket',
            self::Fashion => 'Butik, pakaian & aksesoris',
            self::Gadget => 'Gadget, seluler & pulsa',
            self::Electronics => 'Toko elektronik',
            self::BuildingSupplies => 'Furnitur & bahan bangunan',
            self::PetShop => 'Pet shop',
            self::Florist => 'Florist',
            self::Laundry => 'Laundry',
            self::Workshop => 'Bengkel & cuci kendaraan',
            self::Printing => 'Printing, fotokopi & ATK',
            self::Repair => 'Reparasi elektronik',
            self::PetSalon => 'Pet salon',
            self::Service => 'Jasa lainnya',
            self::Pharmacy => 'Apotek & toko obat',
            self::Optic => 'Optik',
            self::Clinic => 'Klinik',
            self::Fitness => 'Pusat kebugaran',
            self::Salon => 'Salon & barbershop',
            self::Spa => 'Spa & pijat',
            self::Skincare => 'Skincare & makeup',
            self::NailArt => 'Nail art',
            self::Other => 'Lainnya',
        };
    }

    /** Usaha yang lazim melayani makan di tempat: pilihan Takeaway | Dine-in aktif sejak daftar. */
    public function servesDineIn(): bool
    {
        return in_array($this, [self::CoffeeShop, self::Restaurant, self::StreetFood, self::Bakery, self::Beverage], true);
    }

    /** Hanya usaha makanan & minuman yang ditanya cara berjualan (bawa pulang / makan di tempat). */
    public function asksSalesMode(): bool
    {
        return $this->group() === BusinessGroup::Food;
    }
}
