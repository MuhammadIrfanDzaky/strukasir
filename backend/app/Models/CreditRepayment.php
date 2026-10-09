<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Pelunasan kasbon (append-only). `kind=reversal` membatalkan pelunasan lain (`reversal_of`). */
class CreditRepayment extends Model
{
    use BelongsToTenant;

    public const UPDATED_AT = null;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = ['tenant_id'];

    protected function casts(): array
    {
        return ['amount' => 'integer', 'tendered' => 'integer', 'change' => 'integer', 'created_at' => 'datetime'];
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function confirmer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'confirmed_by');
    }
}
