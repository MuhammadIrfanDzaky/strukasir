<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Tagihan paket lewat payment gateway (QRIS Midtrans). Harga & diskon dikunci saat tagihan dibuat;
 * status hanya diubah dari server (notifikasi bertanda tangan + cek status ke Midtrans), tidak dari app.
 * Tabel platform (lintas usaha), tanpa RLS — sama seperti `subscription_payments`.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('subscription_invoices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('plan_id')->constrained('plans');
            $table->string('period', 10);
            $table->unsignedInteger('base_amount');
            $table->unsignedTinyInteger('discount_percent')->default(0);
            $table->string('discount_reason', 20)->nullable();
            $table->unsignedInteger('amount');
            $table->string('gateway', 20)->default('midtrans');
            $table->string('order_id', 50)->unique(); // dikirim ke gateway; kunci idempotensi notifikasi
            $table->string('gateway_ref', 100)->nullable(); // transaction_id Midtrans
            $table->string('status', 10)->default('pending');
            $table->text('qr_string')->nullable();
            $table->string('qr_url', 500)->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->foreignUuid('payment_id')->nullable()->constrained('subscription_payments')->nullOnDelete();
            $table->timestamps();
            $table->index(['tenant_id', 'created_at']);
        });
        DB::statement("ALTER TABLE subscription_invoices ADD CONSTRAINT subscription_invoices_status_check CHECK (status IN ('pending', 'paid', 'expired', 'failed'))");
        DB::statement("ALTER TABLE subscription_invoices ADD CONSTRAINT subscription_invoices_period_check CHECK (period IN ('month', 'quarter', 'half', 'year'))");
    }

    public function down(): void
    {
        Schema::dropIfExists('subscription_invoices');
    }
};
