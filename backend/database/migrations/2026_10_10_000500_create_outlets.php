<?php

use App\Support\Database\Rls;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Multi-outlet (fitur `multi_outlet`). Satu usaha (tenant) punya satu atau lebih outlet; menu, pelanggan,
 * promo, & staf tetap satu untuk semua outlet. Yang terikat ke outlet: tablet (`devices`), shift, order,
 * dan stok bahan (`ingredient_stocks` per outlet, `stock_movements.outlet_id`). Kas keluar/masuk &
 * pelunasan kasbon ikut outlet lewat shift-nya.
 *
 * Setiap usaha yang sudah ada mendapat satu outlet utama (kode O1); semua data lama masuk ke sana.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('outlets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('code', 10); // O1, O2, …
            $table->string('name', 60);
            $table->string('address', 160)->nullable(); // alamat di struk outlet ini
            $table->string('phone', 20)->nullable();
            $table->boolean('active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->unique(['tenant_id', 'code']);
            $table->unique(['tenant_id', 'name']);
        });
        Rls::enable('outlets');

        Schema::table('devices', fn (Blueprint $t) => $t->uuid('outlet_id')->nullable());
        Schema::table('shifts', fn (Blueprint $t) => $t->uuid('outlet_id')->nullable());
        Schema::table('orders', fn (Blueprint $t) => $t->uuid('outlet_id')->nullable());
        Schema::table('stock_movements', fn (Blueprint $t) => $t->uuid('outlet_id')->nullable());

        Schema::create('ingredient_stocks', function (Blueprint $table) {
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('outlet_id');
            $table->uuid('ingredient_id');
            $table->decimal('stock', 14, 3)->default(0);
            $table->decimal('avg_cost', 16, 4)->default(0); // Rp per satuan, per outlet (harga beli bisa beda)
            $table->timestamps();

            $table->primary(['outlet_id', 'ingredient_id']);
            $table->index(['tenant_id', 'ingredient_id']);
            $table->foreign(['tenant_id', 'outlet_id'])->references(['tenant_id', 'id'])->on('outlets');
            $table->foreign(['tenant_id', 'ingredient_id'])->references(['tenant_id', 'id'])->on('ingredients');
        });
        DB::statement('ALTER TABLE ingredient_stocks ADD CONSTRAINT ingredient_stocks_cost_check CHECK (avg_cost >= 0)');
        Rls::enable('ingredient_stocks');

        // Data lama → outlet utama tiap usaha (lintas tenant: RLS dilewati hanya di migrasi ini).
        app(TenantContext::class)->bypass(function () {
            DB::statement('ALTER TABLE stock_movements DISABLE TRIGGER stock_movements_append_only');
            foreach (DB::table('tenants')->get(['id', 'name']) as $tenant) {
                $outlet = (string) Str::uuid();
                DB::table('outlets')->insert([
                    'id' => $outlet, 'tenant_id' => $tenant->id, 'code' => 'O1', 'name' => mb_substr($tenant->name, 0, 60),
                    'created_at' => now(), 'updated_at' => now(),
                ]);
                DB::table('devices')->where('tenant_id', $tenant->id)->update(['outlet_id' => $outlet]);
                DB::table('stock_movements')->where('tenant_id', $tenant->id)->update(['outlet_id' => $outlet]);
                foreach (DB::table('ingredients')->where('tenant_id', $tenant->id)->get() as $i) {
                    DB::table('ingredient_stocks')->insert([
                        'tenant_id' => $tenant->id, 'outlet_id' => $outlet, 'ingredient_id' => $i->id,
                        'stock' => $i->stock, 'avg_cost' => $i->avg_cost, 'created_at' => now(), 'updated_at' => now(),
                    ]);
                }
            }
            DB::statement('UPDATE shifts SET outlet_id = d.outlet_id FROM devices d WHERE d.id = shifts.device_id');
            DB::statement('UPDATE orders SET outlet_id = d.outlet_id FROM devices d WHERE d.id = orders.device_id');
            DB::statement('ALTER TABLE stock_movements ENABLE TRIGGER stock_movements_append_only');

            // Validasi FK berjalan dengan RLS (FORCE) → tetap di dalam bypass.
            foreach (['devices', 'shifts', 'orders', 'stock_movements'] as $t) {
                DB::statement("ALTER TABLE {$t} ALTER COLUMN outlet_id SET NOT NULL");
                Schema::table($t, function (Blueprint $table) {
                    $table->foreign(['tenant_id', 'outlet_id'])->references(['tenant_id', 'id'])->on('outlets');
                });
            }
        });
        Schema::table('orders', fn (Blueprint $t) => $t->index(['tenant_id', 'outlet_id', 'business_date']));
        Schema::table('shifts', fn (Blueprint $t) => $t->index(['tenant_id', 'outlet_id', 'opened_at']));
        Schema::table('stock_movements', fn (Blueprint $t) => $t->index(['tenant_id', 'outlet_id', 'ingredient_id']));
        Schema::table('ingredients', fn (Blueprint $t) => $t->dropColumn(['stock', 'avg_cost']));

        DB::table('features')->insertOrIgnore([
            'key' => 'multi_outlet',
            'description' => 'Lebih dari satu outlet: menu & pelanggan bersama, stok & laporan per outlet',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        foreach (DB::table('plans')->pluck('id') as $planId) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $planId, 'feature_key' => 'multi_outlet']);
        }
    }

    public function down(): void
    {
        Schema::table('ingredients', function (Blueprint $t) {
            $t->decimal('stock', 14, 3)->default(0);
            $t->decimal('avg_cost', 16, 4)->default(0);
        });
        Schema::dropIfExists('ingredient_stocks');
        foreach (['devices', 'shifts', 'orders', 'stock_movements'] as $t) {
            Schema::table($t, function (Blueprint $table) {
                $table->dropForeign(['tenant_id', 'outlet_id']);
                $table->dropColumn('outlet_id');
            });
        }
        Schema::dropIfExists('outlets');
        DB::table('features')->where('key', 'multi_outlet')->delete();
    }
};
