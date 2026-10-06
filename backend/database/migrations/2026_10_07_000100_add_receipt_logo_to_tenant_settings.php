<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Logo struk per kedai: PNG hitam-putih (≤ 384 px, lebar cetak printer 58 mm) disimpan sebagai
 * base64 di database, bukan file. Jadi tidak ada path/bucket (SEC-04, SEC-28) dan logo ikut backup.
 * Batas ukuran dijaga juga di DB: 64 KB biner ≈ 87.400 karakter base64.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->text('receipt_logo')->nullable();
        });
        DB::statement('ALTER TABLE tenant_settings ADD CONSTRAINT tenant_settings_logo_size_check'
            .' CHECK (receipt_logo IS NULL OR length(receipt_logo) <= 87400)');
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE tenant_settings DROP CONSTRAINT IF EXISTS tenant_settings_logo_size_check');
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->dropColumn('receipt_logo');
        });
    }
};
