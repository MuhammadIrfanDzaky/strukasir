<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Promo: beberapa rentang jam per promo (mis. 12:00–14:00 dan 19:00–21:00) & tipe baru.
 * - times: [{start: "HH:mm", end: "HH:mm"}, …] maks. 4; null = sepanjang hari (menggantikan start_time/end_time)
 * - price (harga spesial: value = harga jual per item), min_qty (beli minimal buy_qty → diskon value bp),
 *   bundle (paket: bundle_items [{product_id, qty}] dijual seharga value)
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('promotions', function (Blueprint $table) {
            $table->json('times')->nullable();
            $table->json('bundle_items')->nullable();
        });
        DB::statement("UPDATE promotions SET times = json_build_array(json_build_object(
            'start', to_char(start_time, 'HH24:MI'), 'end', to_char(end_time, 'HH24:MI')))
            WHERE start_time IS NOT NULL AND end_time IS NOT NULL");
        Schema::table('promotions', function (Blueprint $table) {
            $table->dropColumn(['start_time', 'end_time']);
        });

        DB::statement('ALTER TABLE promotions DROP CONSTRAINT promotions_type_check');
        DB::statement("ALTER TABLE promotions ADD CONSTRAINT promotions_type_check CHECK (
            (type = 'percent' AND value BETWEEN 1 AND 10000)
            OR (type = 'amount' AND value > 0)
            OR (type = 'price')
            OR (type = 'min_qty' AND buy_qty >= 2 AND value BETWEEN 1 AND 10000)
            OR (type = 'bogo' AND buy_qty >= 1 AND free_qty >= 1)
            OR (type = 'bundle' AND value > 0 AND bundle_items IS NOT NULL))");
    }

    public function down(): void
    {
        DB::table('promotions')->whereNotIn('type', ['percent', 'amount', 'bogo'])->delete();
        DB::statement('ALTER TABLE promotions DROP CONSTRAINT promotions_type_check');
        DB::statement("ALTER TABLE promotions ADD CONSTRAINT promotions_type_check CHECK (
            (type = 'percent' AND value BETWEEN 1 AND 10000)
            OR (type = 'amount' AND value > 0)
            OR (type = 'bogo' AND buy_qty >= 1 AND free_qty >= 1))");
        Schema::table('promotions', function (Blueprint $table) {
            $table->time('start_time')->nullable();
            $table->time('end_time')->nullable();
        });
        DB::statement("UPDATE promotions SET start_time = (times->0->>'start')::time, end_time = (times->0->>'end')::time WHERE times IS NOT NULL");
        Schema::table('promotions', function (Blueprint $table) {
            $table->dropColumn(['times', 'bundle_items']);
        });
    }
};
