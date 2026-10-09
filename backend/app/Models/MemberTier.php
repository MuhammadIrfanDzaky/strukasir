<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Tingkat member: ambang (Rp / kunjungan) + manfaat (diskon %, pengali stempel/poin). */
class MemberTier extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['name', 'threshold', 'discount_bp', 'earn_multiplier', 'color', 'active'];

    protected function casts(): array
    {
        return ['threshold' => 'integer', 'discount_bp' => 'integer', 'earn_multiplier' => 'integer', 'active' => 'boolean'];
    }
}
