<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * 2FA (TOTP) untuk owner, dipakai saat mendaftarkan tablet (SEC-19).
 * - two_factor_secret: terenkripsi dengan APP_KEY (cast `encrypted`).
 * - two_factor_confirmed_at: 2FA baru berlaku setelah owner memasukkan satu kode yang benar.
 * - two_factor_last_step: langkah waktu TOTP terakhir yang dipakai → kode tidak bisa dipakai ulang.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->text('two_factor_secret')->nullable();
            $table->timestamp('two_factor_confirmed_at')->nullable();
            $table->unsignedBigInteger('two_factor_last_step')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['two_factor_secret', 'two_factor_confirmed_at', 'two_factor_last_step']);
        });
    }
};
