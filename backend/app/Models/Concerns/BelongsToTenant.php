<?php

namespace App\Models\Concerns;

use App\Models\Tenant;
use App\Support\Tenancy\MissingTenantContext;
use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantScope;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Wajib dipakai setiap model milik tenant. Query otomatis difilter per tenant aktif dan
 * `tenant_id` diisi dari konteks server saat membuat baris baru (tidak pernah dari request).
 */
trait BelongsToTenant
{
    public static function bootBelongsToTenant(): void
    {
        static::addGlobalScope(new TenantScope);

        static::creating(function ($model) {
            $context = app(TenantContext::class);

            if (! $context->has()) {
                if ($context->bypassing() && $model->tenant_id) {
                    return;
                }
                throw MissingTenantContext::for($model::class);
            }

            $model->tenant_id = $context->id();
        });
    }

    public function requiresTenantContext(): bool
    {
        return true;
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }
}
