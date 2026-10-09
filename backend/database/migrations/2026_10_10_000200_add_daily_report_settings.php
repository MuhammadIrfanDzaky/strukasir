<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** Laporan tutup shift ke owner: email otomatis (bisa dimatikan) & nomor WhatsApp tujuan. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->boolean('report_email')->default(true);
            $table->string('report_whatsapp', 20)->nullable(); // null = pakai no HP saat daftar
        });
    }

    public function down(): void
    {
        Schema::table('tenant_settings', fn (Blueprint $t) => $t->dropColumn(['report_email', 'report_whatsapp']));
    }
};
