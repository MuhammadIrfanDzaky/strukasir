<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Stok bahan baku & resep (fitur `inventory`).
 *
 * - `ingredients`: bahan (susu, biji kopi, cup) dengan satuan dasar g / ml / pcs, stok berjalan,
 *   batas stok menipis, dan modal rata-rata (Rp per satuan, rata-rata bergerak dari pembelian).
 * - `recipe_items`: pemakaian bahan per 1 produk, atau per 1 pilihan varian (qty boleh negatif
 *   untuk varian pengganti, mis. Oat milk: +150 ml oat, −150 ml susu sapi).
 * - `stock_movements`: buku besar stok, append-only. Penjualan memotong stok saat order lunas,
 *   void mengembalikannya; pembelian, terbuang, dan stok opname dicatat sebagai baris baru.
 *   `ingredients.stock` = jumlah semua baris (dijaga di transaksi yang sama).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ingredients', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 60);
            $table->string('unit', 3); // g | ml | pcs
            $table->decimal('stock', 14, 3)->default(0);
            $table->decimal('min_stock', 14, 3)->nullable(); // null = tanpa peringatan
            $table->decimal('avg_cost', 16, 4)->default(0); // Rp per satuan
            $table->boolean('active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->unique(['tenant_id', 'name']);
        });
        DB::statement("ALTER TABLE ingredients ADD CONSTRAINT ingredients_unit_check CHECK (unit IN ('g', 'ml', 'pcs'))");
        DB::statement('ALTER TABLE ingredients ADD CONSTRAINT ingredients_cost_check CHECK (avg_cost >= 0 AND (min_stock IS NULL OR min_stock >= 0))');

        Schema::create('recipe_items', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('product_id')->nullable();
            $table->uuid('modifier_id')->nullable();
            $table->uuid('ingredient_id');
            $table->decimal('qty', 12, 3);
            $table->timestamps();

            $table->unique(['tenant_id', 'product_id', 'ingredient_id']);
            $table->unique(['tenant_id', 'modifier_id', 'ingredient_id']);
            $table->index(['tenant_id', 'ingredient_id']);
            $table->foreign(['tenant_id', 'product_id'])->references(['tenant_id', 'id'])->on('products')->cascadeOnDelete();
            $table->foreign(['tenant_id', 'modifier_id'])->references(['tenant_id', 'id'])->on('modifiers')->cascadeOnDelete();
            $table->foreign(['tenant_id', 'ingredient_id'])->references(['tenant_id', 'id'])->on('ingredients');
        });
        DB::statement('ALTER TABLE recipe_items ADD CONSTRAINT recipe_items_target_check CHECK (
            (product_id IS NOT NULL AND modifier_id IS NULL AND qty > 0)
            OR (product_id IS NULL AND modifier_id IS NOT NULL AND qty <> 0))');

        Schema::create('stock_movements', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('ingredient_id');
            $table->string('kind', 10); // purchase | sale | void | waste | count
            $table->decimal('qty', 14, 3); // + masuk, − keluar
            $table->decimal('unit_cost', 16, 4)->default(0); // Rp per satuan saat itu (pembelian: harga beli)
            $table->decimal('balance_after', 14, 3);
            $table->uuid('batch_id')->nullable(); // satu pembelian / opname / catatan terbuang (ID dari tablet)
            $table->uuid('order_id')->nullable();
            $table->string('supplier', 60)->nullable();
            $table->string('note', 120)->nullable();
            $table->uuid('created_by')->nullable();
            $table->timestamp('created_at', 6)->useCurrent(); // mikrodetik: urutan riwayat tetap benar

            $table->unique(['tenant_id', 'id']);
            $table->unique(['tenant_id', 'batch_id', 'ingredient_id']);
            $table->index(['tenant_id', 'ingredient_id', 'created_at']);
            $table->index(['tenant_id', 'order_id']);
            $table->index(['tenant_id', 'created_at']);
            $table->foreign(['tenant_id', 'ingredient_id'])->references(['tenant_id', 'id'])->on('ingredients');
            $table->foreign(['tenant_id', 'created_by'])->references(['tenant_id', 'id'])->on('users');
        });
        DB::statement("ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_kind_check CHECK (
            (kind = 'purchase' AND qty > 0)
            OR (kind IN ('sale', 'void') AND qty <> 0 AND order_id IS NOT NULL)
            OR (kind = 'waste' AND qty < 0)
            OR kind = 'count')");

        foreach (['ingredients', 'recipe_items', 'stock_movements'] as $t) {
            Rls::enable($t);
        }
        Rls::appendOnly('stock_movements');

        DB::table('features')->insertOrIgnore([
            'key' => 'inventory',
            'description' => 'Stok bahan baku & resep: potong stok otomatis, pembelian, stok opname, peringatan stok menipis, HPP otomatis',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        foreach (DB::table('plans')->pluck('id') as $planId) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $planId, 'feature_key' => 'inventory']);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_movements');
        Schema::dropIfExists('recipe_items');
        Schema::dropIfExists('ingredients');
        DB::table('features')->where('key', 'inventory')->delete();
    }
};
