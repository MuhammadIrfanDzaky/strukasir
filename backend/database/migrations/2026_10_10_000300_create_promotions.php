<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Promo otomatis terjadwal & voucher kode (fitur `promotions`).
 *
 * Promo: potongan % / Rp per item / beli X gratis Y, untuk semua produk / kategori / produk tertentu,
 * berlaku pada hari & jam tertentu dan rentang tanggal opsional. Diterapkan sebagai diskon baris
 * (yang terbesar antara promo dan tingkat member), jadi mesin harga tidak berubah.
 * Voucher: kode → diskon order (% dengan batas, atau Rp), minimal belanja, masa berlaku, kuota.
 * Pemakaian voucher = order lunas yang memakainya (void mengembalikan kuota).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('promotions', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 40);
            $table->string('type', 10); // percent | amount | bogo
            $table->unsignedBigInteger('value')->default(0); // bp (percent) / Rp per item (amount)
            $table->unsignedSmallInteger('buy_qty')->default(0); // bogo: beli X …
            $table->unsignedSmallInteger('free_qty')->default(0); // … gratis Y
            $table->string('scope', 10)->default('all'); // all | categories | products
            $table->json('target_ids')->nullable();
            $table->json('days')->nullable(); // ISO 1=Senin … 7=Minggu; null = setiap hari
            $table->time('start_time')->nullable();
            $table->time('end_time')->nullable();
            $table->date('starts_on')->nullable();
            $table->date('ends_on')->nullable();
            $table->boolean('active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
        });
        DB::statement("ALTER TABLE promotions ADD CONSTRAINT promotions_type_check CHECK (
            (type = 'percent' AND value BETWEEN 1 AND 10000)
            OR (type = 'amount' AND value > 0)
            OR (type = 'bogo' AND buy_qty >= 1 AND free_qty >= 1))");
        DB::statement("ALTER TABLE promotions ADD CONSTRAINT promotions_scope_check CHECK (scope IN ('all', 'categories', 'products'))");

        Schema::create('vouchers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('code', 20); // huruf besar
            $table->string('type', 10); // percent | amount
            $table->unsignedBigInteger('value');
            $table->unsignedBigInteger('max_discount')->nullable(); // batas potongan untuk %
            $table->unsignedBigInteger('min_spend')->default(0);
            $table->date('starts_on')->nullable();
            $table->date('ends_on')->nullable();
            $table->unsignedInteger('usage_limit')->nullable(); // null = tanpa batas
            $table->boolean('active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->unique(['tenant_id', 'code']);
        });
        DB::statement("ALTER TABLE vouchers ADD CONSTRAINT vouchers_type_check CHECK (
            (type = 'percent' AND value BETWEEN 1 AND 10000) OR (type = 'amount' AND value > 0))");

        foreach (['promotions', 'vouchers'] as $t) {
            Rls::enable($t);
        }

        Schema::table('order_items', function (Blueprint $table) {
            $table->string('promo_name', 40)->nullable(); // promo yang memberi diskon baris ini
        });
        Schema::table('orders', function (Blueprint $table) {
            $table->uuid('voucher_id')->nullable();
            $table->string('voucher_code', 20)->nullable();
            $table->unsignedBigInteger('voucher_discount')->default(0);
            $table->unsignedBigInteger('promo_discount')->default(0);
            $table->index(['tenant_id', 'voucher_id']);
        });

        DB::table('features')->insertOrIgnore([
            'key' => 'promotions',
            'description' => 'Promo otomatis terjadwal (happy hour, beli X gratis Y) & voucher kode',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        foreach (DB::table('plans')->pluck('id') as $planId) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $planId, 'feature_key' => 'promotions']);
        }
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropIndex(['tenant_id', 'voucher_id']);
            $table->dropColumn(['voucher_id', 'voucher_code', 'voucher_discount', 'promo_discount']);
        });
        Schema::table('order_items', fn (Blueprint $t) => $t->dropColumn('promo_name'));
        Schema::dropIfExists('vouchers');
        Schema::dropIfExists('promotions');
        DB::table('features')->where('key', 'promotions')->delete();
    }
};
