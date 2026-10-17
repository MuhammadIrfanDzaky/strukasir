<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * QRIS statis milik kedai: gambar kode QR (PNG hitam-putih dari tablet, base64) ditampilkan ke pembeli
 * saat bayar QRIS dan opsional dicetak di bill belum dibayar. Dana tetap masuk langsung ke rekening
 * merchant QRIS pemilik usaha; Strukasir tidak memegang uang.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->text('qris_image')->nullable();
            $table->boolean('qris_on_bill')->default(true);
        });
    }

    public function down(): void
    {
        Schema::table('tenant_settings', fn (Blueprint $table) => $table->dropColumn(['qris_image', 'qris_on_bill']));
    }
};
