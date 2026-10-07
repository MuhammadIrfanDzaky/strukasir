<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Daftar jenis usaha berkelompok (30 pilihan, kode lama tetap berlaku), isian "Lainnya, sebutkan",
 * dan alamat terstruktur: kode provinsi & kota/kabupaten Kemendagri (mis. 12 / 12.71).
 */
return new class extends Migration
{
    private const SECTORS = [
        'coffee_shop', 'restaurant', 'street_food', 'catering', 'bakery', 'beverage', 'frozen_food',
        'retail', 'minimarket', 'fashion', 'gadget', 'electronics', 'building_supplies', 'pet_shop', 'florist',
        'laundry', 'workshop', 'printing', 'repair', 'pet_salon', 'service',
        'pharmacy', 'optic', 'clinic', 'fitness',
        'salon', 'spa', 'skincare', 'nail_art',
        'other',
    ];

    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->string('sector_other', 60)->nullable();
            $table->string('province_code', 2)->nullable();
            $table->string('regency_code', 5)->nullable();
        });

        DB::statement('ALTER TABLE tenants DROP CONSTRAINT tenants_sector_check');
        DB::statement("ALTER TABLE tenants ADD CONSTRAINT tenants_sector_check CHECK (sector IN ('"
            .implode("', '", self::SECTORS)."'))");
        // Kode kab/kota selalu diawali kode provinsinya.
        DB::statement('ALTER TABLE tenants ADD CONSTRAINT tenants_region_check CHECK'
            ." (regency_code IS NULL OR (province_code IS NOT NULL AND regency_code LIKE province_code || '.%'))");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE tenants DROP CONSTRAINT tenants_region_check');
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['sector_other', 'province_code', 'regency_code']);
        });
        DB::statement('ALTER TABLE tenants DROP CONSTRAINT tenants_sector_check');
        DB::statement('ALTER TABLE tenants ADD CONSTRAINT tenants_sector_check CHECK (sector IN'
            ." ('coffee_shop', 'restaurant', 'street_food', 'bakery', 'retail', 'service', 'other'))");
    }
};
