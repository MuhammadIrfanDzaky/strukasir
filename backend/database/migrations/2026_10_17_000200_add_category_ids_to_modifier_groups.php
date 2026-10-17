<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Grup pilihan "muncul di kategori": produk baru di kategori itu langsung memakai grup ini, dan form
 * produk hanya menawarkan grup yang relevan (kopi tidak ditawari level pedas). Kosong = belum diatur.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('modifier_groups', function (Blueprint $table) {
            $table->json('category_ids')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('modifier_groups', fn (Blueprint $table) => $table->dropColumn('category_ids'));
    }
};
