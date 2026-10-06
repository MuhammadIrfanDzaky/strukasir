<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

class Product extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['category_id', 'code', 'name', 'price', 'cost', 'active', 'sold_out', 'favorite', 'sort'];

    protected function casts(): array
    {
        return [
            'price' => 'integer',
            'cost' => 'integer',
            'active' => 'boolean',
            'sold_out' => 'boolean',
            'favorite' => 'boolean',
        ];
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    public function modifierGroups(): BelongsToMany
    {
        return $this->belongsToMany(ModifierGroup::class, 'product_modifier_groups')
            ->withPivot(['tenant_id', 'sort'])
            ->orderByPivot('sort');
    }
}
