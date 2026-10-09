<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Pesan WhatsApp ke member (fitur `customer_messaging`, butuh `customers`): versi gratis lewat tautan
 * wa.me — server menyusun teks dari template, tablet membuka WhatsApp, kasir/owner menekan kirim.
 * `message_templates` = teks yang diubah owner (tanpa baris = teks bawaan); `message_logs` = riwayat
 * pesan yang disiapkan (siapa, kapan, ke siapa, template apa) agar tidak terkirim dobel.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('message_templates', function (Blueprint $table) {
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('key', 20);
            $table->text('body');
            $table->timestamps();

            $table->primary(['tenant_id', 'key']);
        });

        Schema::create('message_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('customer_id');
            $table->string('template', 20);
            $table->uuid('order_id')->nullable();
            $table->uuid('sent_by');
            $table->timestamp('created_at')->useCurrent();

            $table->index(['tenant_id', 'template', 'customer_id', 'created_at']);
            $table->foreign(['tenant_id', 'customer_id'])->references(['tenant_id', 'id'])->on('customers');
            $table->foreign(['tenant_id', 'sent_by'])->references(['tenant_id', 'id'])->on('users');
        });

        foreach (['message_templates', 'message_logs'] as $t) {
            Rls::enable($t);
        }

        DB::table('features')->insertOrIgnore([
            'key' => 'customer_messaging',
            'description' => 'Pesan WhatsApp ke member: struk digital, ucapan ulang tahun, sapa pelanggan lama, pengingat kasbon',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        foreach (DB::table('plans')->pluck('id') as $planId) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $planId, 'feature_key' => 'customer_messaging']);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('message_logs');
        Schema::dropIfExists('message_templates');
        DB::table('features')->where('key', 'customer_messaging')->delete();
    }
};
