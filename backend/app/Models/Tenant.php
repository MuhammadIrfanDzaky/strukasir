<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Tenant extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = ['code', 'name', 'timezone'];

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    public function settings(): HasOne
    {
        return $this->hasOne(TenantSetting::class);
    }

    public function isActive(): bool
    {
        return $this->status === 'active';
    }
}
