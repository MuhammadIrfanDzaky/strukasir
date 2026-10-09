<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Program loyalitas (fitur `loyalty`, butuh `customers`): satu program per kedai yang dirakit owner
 * dari blok — cara dapat (stempel per item / per transaksi / poin per Rp X) + daftar hadiah
 * (gratis produk / potongan Rp / potongan %) + masa berlaku opsional.
 *
 * Saldo = jumlah `loyalty_entries` (append-only, seperti payments): dapat, tukar, batal (void),
 * hangus, penyesuaian owner. Hadiah di order disimpan sebagai salinan (nama, harga stempel, potongan).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('loyalty_programs', function (Blueprint $table) {
            $table->foreignUuid('tenant_id')->primary()->constrained()->cascadeOnDelete();
            $table->boolean('active')->default(false);
            $table->string('name', 40);
            // per_item: stempel per item (semua / kategori tertentu); per_order: 1 stempel per transaksi
            // (minimal belanja); per_amount: 1 poin per kelipatan Rp.
            $table->string('earn_mode', 12)->default('per_item');
            $table->unsignedInteger('earn_per_amount')->nullable();
            $table->unsignedInteger('earn_min_order')->nullable();
            $table->json('category_ids')->nullable(); // per_item; null/kosong = semua produk
            $table->unsignedSmallInteger('expiry_months')->nullable(); // hangus bila tidak ada transaksi N bulan
            $table->timestamps();
        });
        DB::statement("ALTER TABLE loyalty_programs ADD CONSTRAINT loyalty_programs_mode_check CHECK (earn_mode IN ('per_item', 'per_order', 'per_amount'))");

        Schema::create('loyalty_rewards', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 60);
            $table->unsignedInteger('cost'); // stempel / poin
            $table->string('type', 16); // free_product | amount | percent
            $table->uuid('product_id')->nullable();
            $table->unsignedBigInteger('value')->default(0); // Rp (amount) atau basis poin (percent)
            $table->boolean('active')->default(true);
            $table->unsignedInteger('sort')->default(0);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->foreign(['tenant_id', 'product_id'])->references(['tenant_id', 'id'])->on('products');
        });
        DB::statement("ALTER TABLE loyalty_rewards ADD CONSTRAINT loyalty_rewards_type_check CHECK (
            (type = 'free_product' AND product_id IS NOT NULL)
            OR (type = 'amount' AND value > 0)
            OR (type = 'percent' AND value BETWEEN 1 AND 10000))");
        DB::statement('ALTER TABLE loyalty_rewards ADD CONSTRAINT loyalty_rewards_cost_check CHECK (cost >= 1)');

        Schema::create('loyalty_entries', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('customer_id');
            $table->uuid('order_id')->nullable();
            $table->string('kind', 10); // earn | redeem | reverse | expire | adjust
            $table->integer('units'); // + masuk, − keluar
            $table->uuid('reward_id')->nullable();
            $table->string('note', 120)->nullable();
            $table->uuid('user_id')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->unique(['tenant_id', 'id']);
            $table->index(['tenant_id', 'customer_id', 'created_at']);
            $table->index(['tenant_id', 'order_id']);
            $table->foreign(['tenant_id', 'customer_id'])->references(['tenant_id', 'id'])->on('customers');
            $table->foreign(['tenant_id', 'order_id'])->references(['tenant_id', 'id'])->on('orders');
        });
        DB::statement("ALTER TABLE loyalty_entries ADD CONSTRAINT loyalty_entries_kind_check CHECK (kind IN ('earn', 'redeem', 'reverse', 'expire', 'adjust'))");

        Schema::table('orders', function (Blueprint $table) {
            $table->uuid('reward_id')->nullable();
            $table->string('reward_name', 60)->nullable();
            $table->unsignedInteger('reward_cost')->nullable();
            $table->uuid('reward_item_id')->nullable(); // baris yang digratiskan (hadiah gratis produk)
            $table->unsignedBigInteger('reward_discount')->default(0);
        });

        foreach (['loyalty_programs', 'loyalty_rewards', 'loyalty_entries'] as $t) {
            Rls::enable($t);
        }
        Rls::appendOnly('loyalty_entries');

        DB::table('features')->insertOrIgnore([
            'key' => 'loyalty',
            'description' => 'Program loyalitas: stempel / poin dari belanja member, tukar hadiah',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        foreach (DB::table('plans')->pluck('id') as $planId) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $planId, 'feature_key' => 'loyalty']);
        }
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn(['reward_id', 'reward_name', 'reward_cost', 'reward_item_id', 'reward_discount']);
        });
        Schema::dropIfExists('loyalty_entries');
        Schema::dropIfExists('loyalty_rewards');
        Schema::dropIfExists('loyalty_programs');
        DB::table('features')->where('key', 'loyalty')->delete();
    }
};
