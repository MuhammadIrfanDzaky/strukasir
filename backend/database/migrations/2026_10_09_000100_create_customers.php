<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Modul pelanggan / member (fitur `customers`). Data pribadi sengaja minim (UU PDP): nama, no HP,
 * tanggal lahir, catatan. Pelanggan tidak pernah dihapus fisik karena riwayat order merujuknya;
 * permintaan hapus data = anonimisasi (`anonymized_at`, data pribadi dikosongkan).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('code', 12); // M0001, berurutan per kedai
            $table->string('name', 80);
            $table->string('phone', 20)->nullable(); // format seragam +62…
            $table->date('birth_date')->nullable();
            $table->string('note', 200)->nullable();
            $table->timestamp('anonymized_at')->nullable();
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->unique(['tenant_id', 'code']);
            $table->index(['tenant_id', 'name']);
        });
        // No HP unik per kedai (boleh kosong untuk banyak pelanggan).
        DB::statement('CREATE UNIQUE INDEX customers_tenant_phone_unique ON customers (tenant_id, phone) WHERE phone IS NOT NULL');
        Rls::enable('customers');

        Schema::table('orders', function (Blueprint $table) {
            $table->uuid('customer_id')->nullable()->after('customer_label');
            $table->index(['tenant_id', 'customer_id']);
            $table->foreign(['tenant_id', 'customer_id'])->references(['tenant_id', 'id'])->on('customers');
        });

        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->boolean('customer_phone_required')->default(true);
            // Nomor urut kode member; dinaikkan atomik (UPDATE … RETURNING) agar tablet paralel tidak bentrok.
            $table->unsignedInteger('customer_seq')->default(0);
        });

        // Deploy tidak menjalankan FeatureSeeder: daftarkan fitur & masukkan ke semua paket yang ada.
        // Paket berjenjang nanti cukup menghapus baris plan_features-nya.
        DB::table('features')->insertOrIgnore([
            'key' => 'customers',
            'description' => 'Data pelanggan / member: cari & tautkan ke order, riwayat belanja, kelompok pelanggan',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        foreach (DB::table('plans')->pluck('id') as $planId) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $planId, 'feature_key' => 'customers']);
        }
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropForeign(['tenant_id', 'customer_id']);
            $table->dropIndex(['tenant_id', 'customer_id']);
            $table->dropColumn('customer_id');
        });
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->dropColumn(['customer_phone_required', 'customer_seq']);
        });
        Schema::dropIfExists('customers');
        DB::table('features')->where('key', 'customers')->delete();
    }
};
