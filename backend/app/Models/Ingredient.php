<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Bahan baku (lihat migrasi create_inventory). `stock` & `avg_cost` hanya diubah InventoryService. */
class Ingredient extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['name', 'unit', 'min_stock', 'active'];

    protected function casts(): array
    {
        return ['stock' => 'float', 'min_stock' => 'float', 'avg_cost' => 'float', 'active' => 'boolean'];
    }
}
