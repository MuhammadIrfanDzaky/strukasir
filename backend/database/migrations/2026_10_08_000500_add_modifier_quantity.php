<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Tambahan berjumlah (mis. Extra shot x2): grup pilihan bisa diizinkan memilih satu opsi lebih dari
 * sekali (max_quantity per opsi), dan baris modifier di order menyimpan jumlahnya. Grup & order lama = 1.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('modifier_groups', function (Blueprint $table) {
            $table->boolean('allow_quantity')->default(false);
            $table->unsignedSmallInteger('max_quantity')->default(1);
        });
        DB::statement('ALTER TABLE modifier_groups ADD CONSTRAINT modifier_groups_max_quantity_check CHECK (max_quantity BETWEEN 1 AND 20)');

        Schema::table('order_item_modifiers', function (Blueprint $table) {
            $table->unsignedSmallInteger('qty')->default(1);
        });
        DB::statement('ALTER TABLE order_item_modifiers ADD CONSTRAINT order_item_modifiers_qty_check CHECK (qty BETWEEN 1 AND 20)');
    }

    public function down(): void
    {
        Schema::table('order_item_modifiers', function (Blueprint $table) {
            $table->dropColumn('qty');
        });
        Schema::table('modifier_groups', function (Blueprint $table) {
            $table->dropColumn(['allow_quantity', 'max_quantity']);
        });
    }
};
