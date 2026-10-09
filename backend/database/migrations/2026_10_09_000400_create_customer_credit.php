<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Kasbon / piutang member (fitur `customer_credit`, butuh `customers`).
 *
 * - Bayar dengan kasbon = baris `payments` metode `credit` (order tetap lunas sebagai penjualan;
 *   uangnya belum diterima). Void order → refund `credit` mengurangi piutang.
 * - Pelunasan = `credit_repayments` (append-only, di shift terbuka; tunai ikut kas laci).
 *   Salah catat dibatalkan dengan baris `reversal`, bukan dihapus.
 * - Piutang member = kasbon − refund kasbon − pelunasan + pembatalan pelunasan.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement('ALTER TABLE payments DROP CONSTRAINT payments_method_check');
        DB::statement("ALTER TABLE payments ADD CONSTRAINT payments_method_check CHECK (method IN ('cash', 'debit', 'qris', 'credit'))");

        Schema::table('customers', function (Blueprint $table) {
            $table->unsignedBigInteger('credit_limit')->nullable(); // null = ikut batas default kedai
        });
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->unsignedBigInteger('credit_default_limit')->nullable()->default(500000); // null = tanpa batas
        });

        Schema::create('credit_repayments', function (Blueprint $table) {
            $table->uuid('id')->primary(); // dibuat tablet = idempotency key
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('customer_id');
            $table->uuid('shift_id');
            $table->string('kind', 10)->default('repayment'); // repayment | reversal
            $table->uuid('reversal_of')->nullable();
            $table->string('method', 8);
            $table->unsignedBigInteger('amount');
            $table->unsignedBigInteger('tendered')->nullable();
            $table->unsignedBigInteger('change')->default(0);
            $table->string('note', 120)->nullable();
            $table->uuid('confirmed_by');
            $table->timestamp('created_at')->useCurrent();

            $table->unique(['tenant_id', 'id']);
            $table->unique(['tenant_id', 'reversal_of']); // satu pelunasan dibatalkan paling banyak sekali
            $table->index(['tenant_id', 'customer_id', 'created_at']);
            $table->index(['tenant_id', 'shift_id']);
            $table->foreign(['tenant_id', 'customer_id'])->references(['tenant_id', 'id'])->on('customers');
            $table->foreign(['tenant_id', 'shift_id'])->references(['tenant_id', 'id'])->on('shifts');
            $table->foreign(['tenant_id', 'confirmed_by'])->references(['tenant_id', 'id'])->on('users');
        });
        DB::statement("ALTER TABLE credit_repayments ADD CONSTRAINT credit_repayments_kind_check CHECK (kind IN ('repayment', 'reversal') AND (kind = 'repayment') = (reversal_of IS NULL))");
        DB::statement("ALTER TABLE credit_repayments ADD CONSTRAINT credit_repayments_method_check CHECK (method IN ('cash', 'debit', 'qris'))");
        DB::statement('ALTER TABLE credit_repayments ADD CONSTRAINT credit_repayments_amount_check CHECK (amount > 0)');
        DB::statement("ALTER TABLE credit_repayments ADD CONSTRAINT credit_repayments_cash_check CHECK (method = 'cash' OR (tendered IS NULL AND change = 0))");
        Rls::enable('credit_repayments');
        Rls::appendOnly('credit_repayments');

        DB::table('features')->insertOrIgnore([
            'key' => 'customer_credit',
            'description' => 'Kasbon / piutang member: bayar nanti dengan batas, pelunasan di kasir, laporan piutang',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        foreach (DB::table('plans')->pluck('id') as $planId) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $planId, 'feature_key' => 'customer_credit']);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('credit_repayments');
        Schema::table('tenant_settings', fn (Blueprint $t) => $t->dropColumn('credit_default_limit'));
        Schema::table('customers', fn (Blueprint $t) => $t->dropColumn('credit_limit'));
        DB::statement('ALTER TABLE payments DROP CONSTRAINT payments_method_check');
        DB::statement("ALTER TABLE payments ADD CONSTRAINT payments_method_check CHECK (method IN ('cash', 'debit', 'qris'))");
        DB::table('features')->where('key', 'customer_credit')->delete();
    }
};
