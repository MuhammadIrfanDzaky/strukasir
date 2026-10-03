<?php

namespace Database\Seeders;

use App\Enums\Feature;
use App\Models\Plan;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

/** Daftar fitur & paket dasar. Idempotent — aman dijalankan di produksi setiap deploy. */
class FeatureSeeder extends Seeder
{
    public function run(): void
    {
        foreach (Feature::cases() as $feature) {
            DB::table('features')->updateOrInsert(
                ['key' => $feature->value],
                ['description' => $feature->description(), 'updated_at' => now(), 'created_at' => now()],
            );
        }

        // Untuk saat ini satu paket berisi semua fitur v1. Paket berjenjang menyusul saat ada klien ke-2.
        $plan = Plan::firstOrCreate(['code' => 'standard'], ['name' => 'Standard']);
        foreach (Feature::cases() as $feature) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $plan->id, 'feature_key' => $feature->value]);
        }
    }
}
