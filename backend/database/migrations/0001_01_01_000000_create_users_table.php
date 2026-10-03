<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Tenancy & identitas. Tabel di sini dibaca SEBELUM tenant diketahui (login, resolusi token),
 * sehingga tidak memakai RLS; isolasinya lewat global scope BelongsToTenant + test lintas tenant.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('plans', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('code')->unique();
            $table->string('name');
            $table->timestamps();
        });

        Schema::create('features', function (Blueprint $table) {
            $table->string('key')->primary();
            $table->string('description');
            $table->timestamps();
        });

        Schema::create('plan_features', function (Blueprint $table) {
            $table->foreignUuid('plan_id')->constrained()->cascadeOnDelete();
            $table->string('feature_key');
            $table->foreign('feature_key')->references('key')->on('features')->cascadeOnDelete();
            $table->primary(['plan_id', 'feature_key']);
        });

        Schema::create('tenants', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('code')->unique();
            $table->string('name');
            $table->foreignUuid('plan_id')->constrained();
            $table->string('timezone')->default('Asia/Jakarta');
            $table->string('status')->default('active');
            $table->timestamps();
        });

        Schema::create('users', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            // Email = identitas login owner tanpa memilih kedai, sehingga unik global (lihat docs/adr).
            $table->string('email')->nullable()->unique();
            $table->string('password')->nullable();
            $table->string('pin_hash')->nullable();
            $table->string('role');
            $table->boolean('active')->default(true);
            $table->unsignedSmallInteger('failed_attempts')->default(0);
            $table->timestamp('locked_until')->nullable();
            $table->rememberToken();
            $table->timestamps();

            $table->index(['tenant_id', 'active']);
            $table->unique(['tenant_id', 'name']);
            $table->unique(['tenant_id', 'id']); // target FK komposit dari tabel transaksi
        });
        DB::statement("ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('owner', 'cashier'))");

        Schema::create('devices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('code'); // prefix nomor order, mis. "T1"
            $table->string('name');
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();

            $table->unique(['tenant_id', 'code']);
            $table->unique(['tenant_id', 'id']); // target FK komposit dari tabel transaksi
        });

        Schema::create('sessions', function (Blueprint $table) {
            $table->string('id')->primary();
            $table->foreignUuid('user_id')->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->longText('payload');
            $table->integer('last_activity')->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sessions');
        Schema::dropIfExists('devices');
        Schema::dropIfExists('users');
        Schema::dropIfExists('tenants');
        Schema::dropIfExists('plan_features');
        Schema::dropIfExists('features');
        Schema::dropIfExists('plans');
    }
};
