<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Catatan email pemberitahuan yang sudah dikirim ke usaha (mis. pengingat paket H-3), supaya tidak terkirim
 * dua kali walau tugas terjadwal berjalan ulang. Tabel platform (tanpa RLS).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tenant_notices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('kind', 40); // plan_reminder_3d | plan_reminder_1d | plan_expired
            $table->string('ref', 60); // mis. tanggal akhir paket, supaya periode berikutnya diingatkan lagi
            $table->timestamp('created_at');
            $table->unique(['tenant_id', 'kind', 'ref']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tenant_notices');
    }
};
