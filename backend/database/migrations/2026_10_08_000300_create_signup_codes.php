<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Kode verifikasi email SEBELUM akun dibuat (pendaftaran mandiri). Belum ada user/tenant,
 * jadi dikunci ke alamat email. Hanya hash yang disimpan; berlaku singkat & dibatasi percobaan.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('signup_codes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('email');
            $table->string('code_hash');
            $table->unsignedSmallInteger('attempts')->default(0);
            $table->timestamp('expires_at');
            $table->timestamp('used_at')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['email', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('signup_codes');
    }
};
