<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Fitur baru "customer_name" (nama pelanggan / meja wajib). Deploy tidak menjalankan FeatureSeeder,
 * jadi didaftarkan di sini dan langsung dimasukkan ke semua paket — perilaku kedai lama tidak berubah
 * (nama tetap wajib) sampai owner mematikannya di Pengaturan → Fitur.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::table('features')->insertOrIgnore([
            'key' => 'customer_name',
            'description' => 'Nama pelanggan / nomor meja wajib diisi di setiap order',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        foreach (DB::table('plans')->pluck('id') as $planId) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $planId, 'feature_key' => 'customer_name']);
        }
    }

    public function down(): void
    {
        DB::table('features')->where('key', 'customer_name')->delete();
    }
};
