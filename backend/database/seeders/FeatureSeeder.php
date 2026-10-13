<?php

namespace Database\Seeders;

use App\Support\PlanCatalog;
use Illuminate\Database\Seeder;

/** Daftar fitur & paket (lihat PlanCatalog). Idempotent — aman dijalankan di produksi setiap deploy. */
class FeatureSeeder extends Seeder
{
    public function run(): void
    {
        PlanCatalog::sync();
    }
}
