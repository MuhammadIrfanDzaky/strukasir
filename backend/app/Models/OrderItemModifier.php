<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class OrderItemModifier extends Model
{
    use BelongsToTenant, HasUuids;

    public $timestamps = false;

    protected $fillable = [];

    protected function casts(): array
    {
        return ['price_delta' => 'integer'];
    }
}
