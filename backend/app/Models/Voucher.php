<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Voucher kode → diskon order (lihat migrasi create_promotions). */
class Voucher extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['code', 'type', 'value', 'max_discount', 'min_spend', 'starts_on', 'ends_on', 'usage_limit', 'active'];

    protected function casts(): array
    {
        return [
            'value' => 'integer', 'max_discount' => 'integer', 'min_spend' => 'integer', 'usage_limit' => 'integer',
            'active' => 'boolean', 'starts_on' => 'date', 'ends_on' => 'date',
        ];
    }
}
