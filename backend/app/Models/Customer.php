<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Pelanggan / member kedai. `code` diisi server (CustomerService), tidak pernah dari request.
 */
class Customer extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['name', 'phone', 'birth_date', 'note'];

    protected function casts(): array
    {
        return ['birth_date' => 'date', 'anonymized_at' => 'datetime'];
    }

    public function orders(): HasMany
    {
        return $this->hasMany(Order::class);
    }

    public function isAnonymized(): bool
    {
        return $this->anonymized_at !== null;
    }

    /** @param  Builder<Customer>  $query */
    public function scopeActive(Builder $query): void
    {
        $query->whereNull('anonymized_at');
    }
}
