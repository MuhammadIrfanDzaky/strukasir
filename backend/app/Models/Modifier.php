<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Modifier extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['modifier_group_id', 'name', 'price_delta', 'active', 'sort'];

    protected function casts(): array
    {
        return ['price_delta' => 'integer', 'active' => 'boolean'];
    }

    public function group(): BelongsTo
    {
        return $this->belongsTo(ModifierGroup::class, 'modifier_group_id');
    }
}
