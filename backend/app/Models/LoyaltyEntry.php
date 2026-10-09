<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Baris buku stempel/poin (append-only). Saldo pelanggan = jumlah `units`. */
class LoyaltyEntry extends Model
{
    use BelongsToTenant, HasUuids;

    public const UPDATED_AT = null;

    protected $guarded = ['id', 'tenant_id'];

    protected function casts(): array
    {
        return ['units' => 'integer', 'created_at' => 'datetime'];
    }
}
