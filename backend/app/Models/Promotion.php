<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Promo otomatis terjadwal (lihat migrasi create_promotions). */
class Promotion extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['name', 'type', 'value', 'buy_qty', 'free_qty', 'scope', 'target_ids', 'bundle_items', 'days',
        'times', 'starts_on', 'ends_on', 'active'];

    protected function casts(): array
    {
        return [
            'value' => 'integer', 'buy_qty' => 'integer', 'free_qty' => 'integer',
            'target_ids' => 'array', 'bundle_items' => 'array', 'days' => 'array', 'times' => 'array', 'active' => 'boolean',
            'starts_on' => 'date', 'ends_on' => 'date',
        ];
    }
}
