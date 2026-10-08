<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Tipe pajak per kedai: harga di menu sudah termasuk pajak / service atau belum (terpisah, karena
 * tidak semua kedai memungut service). Order menyimpan tipe saat transaksi supaya struk & cetak
 * ulang tetap benar walau pengaturan diubah.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->boolean('tax_inclusive')->default(false);
            $table->boolean('service_inclusive')->default(false);
        });
        Schema::table('orders', function (Blueprint $table) {
            $table->boolean('tax_inclusive')->default(false);
            $table->boolean('service_inclusive')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn(['tax_inclusive', 'service_inclusive']);
        });
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->dropColumn(['tax_inclusive', 'service_inclusive']);
        });
    }
};
