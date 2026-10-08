<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class ModifierGroup extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['name', 'min_select', 'max_select', 'sort', 'allow_quantity', 'max_quantity'];

    protected function casts(): array
    {
        return ['min_select' => 'integer', 'max_select' => 'integer'];
    }

    public function modifiers(): HasMany
    {
        return $this->hasMany(Modifier::class)->orderBy('sort');
    }
}
