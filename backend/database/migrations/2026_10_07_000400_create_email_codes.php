<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Kode 6 digit yang dikirim ke email owner: verifikasi email & reset password.
 * Hanya hash yang disimpan; berlaku singkat dan dibatasi jumlah percobaan.
 * Seperti `users`, tabel ini dibaca sebelum tenant diketahui (lupa password), jadi tanpa RLS.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->timestamp('email_verified_at')->nullable();
        });

        Schema::create('email_codes', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->string('purpose', 20);
            $table->string('code_hash');
            $table->unsignedSmallInteger('attempts')->default(0);
            $table->timestamp('expires_at');
            $table->timestamp('used_at')->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['user_id', 'purpose', 'created_at']);
        });
        DB::statement("ALTER TABLE email_codes ADD CONSTRAINT email_codes_purpose_check CHECK (purpose IN ('verify_email', 'reset_password'))");
    }

    public function down(): void
    {
        Schema::dropIfExists('email_codes');
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('email_verified_at');
        });
    }
};
