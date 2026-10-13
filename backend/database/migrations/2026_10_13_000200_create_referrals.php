<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Referral antarusaha + catatan pembayaran paket.
 * - Yang diajak: masa coba 14 hari + diskon 25% sekali di pembayaran paket pertama.
 * - Pengajak: satu kupon diskon 50% untuk setiap usaha ajakan yang membayar paket pertama kali.
 * Tabel ini lintas usaha (milik platform), tidak memakai RLS tenant — sama seperti `tenants` & `plans`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            $table->string('referral_code', 12)->nullable()->unique();
            $table->foreignUuid('referred_by')->nullable()->constrained('tenants')->nullOnDelete();
        });

        // Satu baris per pembayaran paket yang diaktifkan admin (harga normal, diskon, yang ditagih).
        Schema::create('subscription_payments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('plan_id')->constrained('plans');
            $table->string('period', 5);
            $table->unsignedInteger('base_amount');
            $table->unsignedTinyInteger('discount_percent')->default(0);
            $table->string('discount_reason', 20)->nullable(); // referred | referral_reward
            $table->unsignedInteger('amount');
            $table->timestamp('created_at');
        });
        DB::statement("ALTER TABLE subscription_payments ADD CONSTRAINT subscription_payments_period_check CHECK (period IN ('month', 'year'))");

        // Kupon pengajak: dibuat saat usaha ajakan membayar pertama kali, dipakai sekali di pembayaran pengajak.
        Schema::create('referral_rewards', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('referrer_id')->constrained('tenants')->cascadeOnDelete();
            $table->foreignUuid('referee_id')->unique()->constrained('tenants')->cascadeOnDelete(); // 1 kupon per usaha ajakan
            $table->unsignedTinyInteger('percent');
            $table->timestamp('created_at');
            $table->foreignUuid('used_payment_id')->nullable()->constrained('subscription_payments')->nullOnDelete();
            $table->timestamp('used_at')->nullable();
            $table->index(['referrer_id', 'used_at']);
        });

        // Kode untuk usaha yang sudah ada.
        foreach (DB::table('tenants')->whereNull('referral_code')->pluck('id') as $id) {
            DB::table('tenants')->where('id', $id)->update(['referral_code' => \App\Services\ReferralService::newCode()]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('referral_rewards');
        Schema::dropIfExists('subscription_payments');
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropConstrainedForeignId('referred_by');
            $table->dropColumn('referral_code');
        });
    }
};
