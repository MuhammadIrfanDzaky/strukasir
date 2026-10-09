<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Tingkat member (fitur `member_tiers`, butuh `customers`): owner membuat tingkat dengan ambang
 * total belanja atau jumlah kunjungan dalam N bulan terakhir; tingkat dihitung otomatis saat dibaca
 * (naik/turun sendiri), atau dikunci manual per pelanggan (`customers.tier_id`).
 * Manfaat: diskon % otomatis + pengali stempel/poin. Salinan tingkat disimpan di order.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('member_tiers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 30);
            $table->unsignedBigInteger('threshold'); // Rp (basis belanja) atau jumlah kunjungan
            $table->unsignedSmallInteger('discount_bp')->default(0); // 500 = 5%
            $table->unsignedSmallInteger('earn_multiplier')->default(1); // stempel/poin ×N
            $table->string('color', 12)->default('silver');
            $table->boolean('active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
        });
        DB::statement('ALTER TABLE member_tiers ADD CONSTRAINT member_tiers_benefit_check CHECK (discount_bp <= 5000 AND earn_multiplier BETWEEN 1 AND 5)');
        Rls::enable('member_tiers');

        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->string('tier_basis', 8)->default('spend'); // spend | visits
            $table->unsignedSmallInteger('tier_window_months')->nullable(); // null = sepanjang waktu
        });

        Schema::table('customers', function (Blueprint $table) {
            $table->uuid('tier_id')->nullable(); // tingkat dikunci manual oleh owner
            $table->foreign(['tenant_id', 'tier_id'])->references(['tenant_id', 'id'])->on('member_tiers');
        });

        Schema::table('orders', function (Blueprint $table) {
            $table->uuid('tier_id')->nullable();
            $table->string('tier_name', 30)->nullable();
            $table->unsignedSmallInteger('tier_discount_bp')->default(0);
            $table->unsignedSmallInteger('tier_multiplier')->default(1);
            $table->unsignedBigInteger('tier_discount')->default(0);
        });

        DB::table('features')->insertOrIgnore([
            'key' => 'member_tiers',
            'description' => 'Tingkat member (mis. Silver/Gold): naik otomatis dari belanja, diskon & pengali stempel',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        foreach (DB::table('plans')->pluck('id') as $planId) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $planId, 'feature_key' => 'member_tiers']);
        }
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn(['tier_id', 'tier_name', 'tier_discount_bp', 'tier_multiplier', 'tier_discount']);
        });
        Schema::table('customers', function (Blueprint $table) {
            $table->dropForeign(['tenant_id', 'tier_id']);
            $table->dropColumn('tier_id');
        });
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->dropColumn(['tier_basis', 'tier_window_months']);
        });
        Schema::dropIfExists('member_tiers');
        DB::table('features')->where('key', 'member_tiers')->delete();
    }
};
