<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Relasi antar tabel tenant memakai FK komposit (tenant_id, x_id) → (tenant_id, id),
 * sehingga database menolak referensi ke baris milik tenant lain.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('categories', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->unsignedInteger('sort')->default(0);
            $table->boolean('active')->default(true);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->unique(['tenant_id', 'name']);
        });

        Schema::create('products', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('category_id');
            $table->string('name');
            $table->unsignedBigInteger('price');
            $table->boolean('active')->default(true);
            $table->boolean('sold_out')->default(false);
            $table->unsignedInteger('sort')->default(0);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->index(['tenant_id', 'category_id']);
            $table->foreign(['tenant_id', 'category_id'])->references(['tenant_id', 'id'])->on('categories');
        });

        Schema::create('modifier_groups', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->unsignedSmallInteger('min_select')->default(0); // >0 = wajib dipilih
            $table->unsignedSmallInteger('max_select')->default(1);
            $table->unsignedInteger('sort')->default(0);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
        });
        DB::statement('ALTER TABLE modifier_groups ADD CONSTRAINT modifier_groups_select_check'
            .' CHECK (max_select >= 1 AND min_select <= max_select)');

        Schema::create('modifiers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('modifier_group_id');
            $table->string('name');
            $table->unsignedBigInteger('price_delta')->default(0);
            $table->boolean('active')->default(true);
            $table->unsignedInteger('sort')->default(0);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->index(['tenant_id', 'modifier_group_id']);
            $table->foreign(['tenant_id', 'modifier_group_id'])->references(['tenant_id', 'id'])
                ->on('modifier_groups')->cascadeOnDelete();
        });

        Schema::create('product_modifier_groups', function (Blueprint $table) {
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('product_id');
            $table->uuid('modifier_group_id');
            $table->unsignedInteger('sort')->default(0);
            $table->primary(['product_id', 'modifier_group_id']);

            $table->foreign(['tenant_id', 'product_id'])->references(['tenant_id', 'id'])
                ->on('products')->cascadeOnDelete();
            $table->foreign(['tenant_id', 'modifier_group_id'])->references(['tenant_id', 'id'])
                ->on('modifier_groups')->cascadeOnDelete();
        });

        foreach (['categories', 'products', 'modifier_groups', 'modifiers', 'product_modifier_groups'] as $t) {
            Rls::enable($t);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('product_modifier_groups');
        Schema::dropIfExists('modifiers');
        Schema::dropIfExists('modifier_groups');
        Schema::dropIfExists('products');
        Schema::dropIfExists('categories');
    }
};
