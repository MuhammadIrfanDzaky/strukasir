<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Kas keluar / masuk di luar penjualan (beli es batu, gas, upah harian, setor ke owner, tambah uang
 * kecil). Dicatat di shift terbuka sehingga "kas seharusnya" saat tutup shift tetap cocok dengan laci.
 * Append-only: salah catat dibatalkan dengan baris pembatalan (`reversal_of`), bukan diedit/dihapus.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('cash_movements', function (Blueprint $table) {
            $table->uuid('id')->primary(); // dibuat tablet = idempotency key
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('shift_id');
            $table->string('kind', 3); // out | in
            $table->string('category', 20);
            $table->unsignedBigInteger('amount');
            $table->string('note', 120)->nullable();
            $table->uuid('reversal_of')->nullable();
            $table->uuid('created_by');
            $table->timestamp('created_at')->useCurrent();

            $table->unique(['tenant_id', 'id']);
            $table->unique(['tenant_id', 'reversal_of']);
            $table->index(['tenant_id', 'shift_id']);
            $table->index(['tenant_id', 'created_at']);
            $table->foreign(['tenant_id', 'shift_id'])->references(['tenant_id', 'id'])->on('shifts');
            $table->foreign(['tenant_id', 'created_by'])->references(['tenant_id', 'id'])->on('users');
        });
        DB::statement("ALTER TABLE cash_movements ADD CONSTRAINT cash_movements_kind_check CHECK (kind IN ('out', 'in'))");
        DB::statement('ALTER TABLE cash_movements ADD CONSTRAINT cash_movements_amount_check CHECK (amount > 0)');
        Rls::enable('cash_movements');
        Rls::appendOnly('cash_movements');
    }

    public function down(): void
    {
        Schema::dropIfExists('cash_movements');
    }
};
