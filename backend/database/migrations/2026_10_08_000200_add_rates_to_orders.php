<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Tarif service & pajak (basis poin) yang berlaku saat order dihitung, supaya kasir & struk
 * menampilkan persennya ("Pajak 10%") dan cetak ulang struk lama tetap benar walau tarif diubah.
 * Order lama bernilai null (persen tidak ditampilkan).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->unsignedInteger('service_bp')->nullable();
            $table->unsignedInteger('tax_bp')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn(['service_bp', 'tax_bp']);
        });
    }
};
