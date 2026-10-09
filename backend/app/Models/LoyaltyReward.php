<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Hadiah yang bisa ditukar: gratis produk, potongan Rp, atau potongan % (value = basis poin). */
class LoyaltyReward extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['name', 'cost', 'type', 'product_id', 'value', 'active', 'sort'];

    protected function casts(): array
    {
        return ['cost' => 'integer', 'value' => 'integer', 'active' => 'boolean', 'sort' => 'integer'];
    }

    public function product(): BelongsTo
    {
        return $this->belongsTo(Product::class);
    }
}
