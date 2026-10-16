<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

// Satuan dasar bahan lebih banyak (kg, L, butir, lembar, sachet, ...): kolom diperlebar & check diperbarui.
return new class extends Migration
{
    public function up(): void
    {
        DB::statement('ALTER TABLE ingredients DROP CONSTRAINT ingredients_unit_check');
        DB::statement('ALTER TABLE ingredients ALTER COLUMN unit TYPE varchar(10)');
        $units = implode(', ', array_map(fn ($u) => "'{$u}'", ['g', 'kg', 'ml', 'L', 'pcs', 'butir', 'lembar', 'potong', 'sachet', 'bungkus', 'botol', 'kaleng', 'cup', 'porsi', 'ikat', 'dus']));
        DB::statement("ALTER TABLE ingredients ADD CONSTRAINT ingredients_unit_check CHECK (unit IN ({$units}))");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE ingredients DROP CONSTRAINT ingredients_unit_check');
        DB::statement("UPDATE ingredients SET unit = 'pcs' WHERE unit NOT IN ('g', 'ml', 'pcs')");
        DB::statement('ALTER TABLE ingredients ALTER COLUMN unit TYPE varchar(3)');
        DB::statement("ALTER TABLE ingredients ADD CONSTRAINT ingredients_unit_check CHECK (unit IN ('g', 'ml', 'pcs'))");
    }
};
