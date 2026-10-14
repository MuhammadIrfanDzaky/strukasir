<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** Gateway pindah dari Midtrans ke Mayar: pelanggan membayar di halaman invoice Mayar (`pay_url`). */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('subscription_invoices', function (Blueprint $table) {
            $table->string('pay_url', 500)->nullable();
            $table->string('gateway', 20)->default('mayar')->change();
            $table->dropColumn(['qr_string', 'qr_url']);
        });
    }

    public function down(): void
    {
        Schema::table('subscription_invoices', function (Blueprint $table) {
            $table->dropColumn('pay_url');
            $table->string('gateway', 20)->default('midtrans')->change();
            $table->text('qr_string')->nullable();
            $table->string('qr_url', 500)->nullable();
        });
    }
};
