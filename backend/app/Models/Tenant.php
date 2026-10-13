<?php

namespace App\Models;

use App\Enums\BusinessSector;
use App\Enums\SalesMode;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Tenant extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = ['code', 'name', 'timezone'];

    protected function casts(): array
    {
        return [
            'sector' => BusinessSector::class,
            'sales_mode' => SalesMode::class,
            'outlet_count' => 'integer',
            'terms_accepted_at' => 'datetime',
            'plan_ends_at' => 'datetime',
            'requested_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        // Kode referral untuk dibagikan owner (lihat ReferralService).
        static::creating(function (Tenant $tenant) {
            $tenant->referral_code ??= \App\Services\ReferralService::newCode();
        });
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    public function requestedPlan(): BelongsTo
    {
        return $this->belongsTo(Plan::class, 'requested_plan_id');
    }

    /** Masa coba / batas bayar / masa langganan sudah lewat: kasir tidak bisa transaksi baru. */
    public function planExpired(): bool
    {
        return $this->plan_ends_at !== null && $this->plan_ends_at->isPast();
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
