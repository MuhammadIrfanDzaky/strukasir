<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Produk: kode (SKU) unik per kedai, harga modal (HPP manual), dan tanda favorit.
 * Item order menyimpan salinan modal saat transaksi (`unit_cost`) supaya laba kotor di laporan
 * tidak berubah ketika owner mengubah modal belakangan. Null = modal belum diisi.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            $table->string('code', 30)->nullable();
            $table->unsignedBigInteger('cost')->nullable();
            $table->boolean('favorite')->default(false);
        });
        // Kode unik per kedai, tanpa membedakan huruf besar/kecil; kosong boleh banyak.
        DB::statement('CREATE UNIQUE INDEX products_tenant_code_unique ON products (tenant_id, lower(code)) WHERE code IS NOT NULL');

        Schema::table('order_items', function (Blueprint $table) {
            $table->unsignedBigInteger('unit_cost')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->dropColumn('unit_cost');
        });
        DB::statement('DROP INDEX IF EXISTS products_tenant_code_unique');
        Schema::table('products', function (Blueprint $table) {
            $table->dropColumn(['code', 'cost', 'favorite']);
        });
    }
};
