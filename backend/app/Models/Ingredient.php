<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Bahan baku (lihat migrasi create_inventory). Stok & modal rata-rata disimpan per outlet di
 * `ingredient_stocks` dan hanya diubah InventoryService; baca lewat scope withStock().
 */
class Ingredient extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['name', 'unit', 'min_stock', 'active'];

    /** Tambah kolom `stock`, `avg_cost`, `outlet_id` milik satu outlet (0 bila belum pernah ada stok di sana). */
    public function scopeWithStock(Builder $query, string $outletId): Builder
    {
        return $query->leftJoin('ingredient_stocks as s', fn ($j) => $j->on('s.ingredient_id', '=', 'ingredients.id')->where('s.outlet_id', '=', $outletId))
            ->select('ingredients.*')
            ->selectRaw('coalesce(s.stock, 0) as stock, coalesce(s.avg_cost, 0) as avg_cost, ?::uuid as outlet_id', [$outletId]);
    }

    protected function casts(): array
    {
        return ['stock' => 'float', 'min_stock' => 'float', 'avg_cost' => 'float', 'active' => 'boolean'];
    }
}
