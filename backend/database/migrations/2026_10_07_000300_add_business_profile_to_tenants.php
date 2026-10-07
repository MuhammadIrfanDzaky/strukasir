<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Profil usaha dari pendaftaran mandiri: sektor, cara jualan, jumlah outlet, telepon,
 * dan kapan owner menyetujui syarat & ketentuan. Kedai lama (dibuat lewat command) bernilai null.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->string('sector', 30)->nullable();
            $table->string('sales_mode', 20)->nullable();
            $table->unsignedSmallInteger('outlet_count')->nullable();
            $table->string('phone', 20)->nullable();
            $table->timestamp('terms_accepted_at')->nullable();
        });

        DB::statement('ALTER TABLE tenants ADD CONSTRAINT tenants_sector_check CHECK (sector IN'
            ." ('coffee_shop', 'restaurant', 'street_food', 'bakery', 'retail', 'service', 'other'))");
        DB::statement("ALTER TABLE tenants ADD CONSTRAINT tenants_sales_mode_check CHECK (sales_mode IN ('takeaway', 'dine_in', 'mixed'))");
        DB::statement('ALTER TABLE tenants ADD CONSTRAINT tenants_outlet_count_check CHECK (outlet_count BETWEEN 1 AND 999)');
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropColumn(['sector', 'sales_mode', 'outlet_count', 'phone', 'terms_accepted_at']);
        });
    }
};
