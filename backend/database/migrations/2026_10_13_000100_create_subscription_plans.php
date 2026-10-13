<?php

use App\Support\PlanCatalog;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Paket berjenjang (Gratis 7 hari, Mulai, Tumbuh, Juragan) + status langganan per usaha.
 * Pembayaran belum otomatis: permintaan upgrade dicatat, paket diaktifkan admin (`pos:activate-plan`).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('plans', function (Blueprint $table) {
            $table->string('tagline', 120)->nullable();
            $table->unsignedInteger('price_month')->default(0); // Rp
            $table->unsignedInteger('price_year')->default(0);
            // null = tanpa batas
            $table->unsignedSmallInteger('max_outlets')->nullable();
            $table->unsignedSmallInteger('max_devices')->nullable();
            $table->unsignedSmallInteger('max_staff')->nullable(); // termasuk owner
            $table->unsignedSmallInteger('sort')->default(0);
            $table->boolean('public')->default(false); // ditawarkan saat daftar & upgrade
        });

        Schema::table('tenants', function (Blueprint $table) {
            // trial = paket gratis 7 hari; awaiting_payment = paket berbayar belum dibayar (boleh dipakai
            // sampai plan_ends_at); active = sudah dibayar sampai plan_ends_at (null = tanpa batas waktu).
            $table->string('plan_status', 20)->default('active');
            $table->timestamp('plan_ends_at')->nullable();
            $table->string('plan_period', 5)->nullable(); // month | year
            // Permintaan upgrade dari app, menunggu pembayaran & aktivasi admin.
            $table->foreignUuid('requested_plan_id')->nullable()->constrained('plans');
            $table->string('requested_period', 5)->nullable();
            $table->timestamp('requested_at')->nullable();
        });
        DB::statement("ALTER TABLE tenants ADD CONSTRAINT tenants_plan_status_check CHECK (plan_status IN ('trial', 'awaiting_payment', 'active'))");
        DB::statement("ALTER TABLE tenants ADD CONSTRAINT tenants_plan_period_check CHECK (plan_period IN ('month', 'year'))");
        DB::statement("ALTER TABLE tenants ADD CONSTRAINT tenants_requested_period_check CHECK (requested_period IN ('month', 'year'))");

        PlanCatalog::sync();

        // Outlet utama usaha yang daftar sendiri: alamat & no HP dari form daftar (dulu tidak ikut tersalin).
        app(TenantContext::class)->bypass(fn () => DB::statement(<<<'SQL'
            UPDATE outlets o
               SET address = COALESCE(o.address, NULLIF(LEFT(s.receipt_header, 160), '')),
                   phone = COALESCE(o.phone, t.phone)
              FROM tenants t
              LEFT JOIN tenant_settings s ON s.tenant_id = t.id
             WHERE o.tenant_id = t.id AND o.code = 'O1' AND t.terms_accepted_at IS NOT NULL
            SQL));
    }

    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropConstrainedForeignId('requested_plan_id');
            $table->dropColumn(['plan_status', 'plan_ends_at', 'plan_period', 'requested_period', 'requested_at']);
        });
        Schema::table('plans', function (Blueprint $table) {
            $table->dropColumn(['tagline', 'price_month', 'price_year', 'max_outlets', 'max_devices', 'max_staff', 'sort', 'public']);
        });
    }
};
