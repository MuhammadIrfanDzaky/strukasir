<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Payment extends Model
{
    use BelongsToTenant, HasUuids;

    /** Append-only (dijaga trigger database): refund = baris baru dengan kind=refund. */
    public const UPDATED_AT = null;

    protected $fillable = [];

    protected function casts(): array
    {
        return ['amount' => 'integer', 'tendered' => 'integer', 'change' => 'integer', 'confirmed_at' => 'datetime'];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }
}
