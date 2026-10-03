<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class OrderItem extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['note'];

    protected function casts(): array
    {
        return ['unit_price' => 'integer', 'qty' => 'integer', 'line_total' => 'integer'];
    }

    public function modifiers(): HasMany
    {
        return $this->hasMany(OrderItemModifier::class);
    }
}
