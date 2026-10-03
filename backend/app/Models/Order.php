<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Order extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['customer_label'];

    protected function casts(): array
    {
        return ['business_date' => 'date', 'client_created_at' => 'datetime', 'paid_at' => 'datetime', 'voided_at' => 'datetime'];
    }

    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class)->orderBy('sort');
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    public function cashier(): BelongsTo
    {
        return $this->belongsTo(User::class, 'cashier_id');
    }
}
