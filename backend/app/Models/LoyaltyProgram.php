<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

/** Satu program loyalitas per kedai (lihat migrasi create_loyalty). */
class LoyaltyProgram extends Model
{
    use BelongsToTenant;

    protected $primaryKey = 'tenant_id';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = ['active', 'name', 'earn_mode', 'earn_per_amount', 'earn_min_order', 'category_ids', 'expiry_months'];

    protected function casts(): array
    {
        return [
            'active' => 'boolean',
            'earn_per_amount' => 'integer',
            'earn_min_order' => 'integer',
            'category_ids' => 'array',
            'expiry_months' => 'integer',
        ];
    }

    /** Stempel (per item / per transaksi) atau poin (per Rp). */
    public function unit(): string
    {
        return $this->earn_mode === 'per_amount' ? 'poin' : 'stempel';
    }
}
