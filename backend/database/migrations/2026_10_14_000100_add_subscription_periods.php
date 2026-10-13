<?php

use App\Support\PlanCatalog;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/** Periode bayar 1 / 3 / 6 / 12 bulan (month, quarter, half, year) dengan diskon 0 / 10 / 15 / 20%. */
return new class extends Migration
{
    private const CHECKS = [
        ['tenants', 'plan_period', 'tenants_plan_period_check'],
        ['tenants', 'requested_period', 'tenants_requested_period_check'],
        ['subscription_payments', 'period', 'subscription_payments_period_check'],
    ];

    public function up(): void
    {
        foreach (self::CHECKS as [$table, $column, $check]) {
            DB::statement("ALTER TABLE {$table} DROP CONSTRAINT {$check}");
            DB::statement("ALTER TABLE {$table} ALTER COLUMN {$column} TYPE varchar(10)");
            DB::statement("ALTER TABLE {$table} ADD CONSTRAINT {$check} CHECK ({$column} IN ('month', 'quarter', 'half', 'year'))");
        }
        PlanCatalog::sync(); // price_year mengikuti diskon 12 bulan yang baru
    }

    public function down(): void
    {
        foreach (self::CHECKS as [$table, $column, $check]) {
            DB::statement("ALTER TABLE {$table} DROP CONSTRAINT {$check}");
            DB::statement("ALTER TABLE {$table} ADD CONSTRAINT {$check} CHECK ({$column} IN ('month', 'year'))");
        }
    }
};
