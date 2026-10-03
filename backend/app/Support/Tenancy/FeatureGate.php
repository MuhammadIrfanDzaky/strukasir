<?php

namespace App\Support\Tenancy;

use App\Enums\Feature;
use App\Models\Tenant;
use Illuminate\Support\Facades\DB;

/**
 * Entitlement tenant: fitur aktif = default paket (plan_features), ditimpa override per tenant
 * (tenant_features). Hasil di-cache per request.
 */
class FeatureGate
{
    /** @var array<string, array<string, bool>> */
    private array $cache = [];

    // Konteks diambil saat dipakai (bukan disimpan di constructor), supaya objek yang hidup lama —
    // mis. controller yang di-cache route atau worker Octane — tidak memegang tenant request lain.
    private function context(): TenantContext
    {
        return app(TenantContext::class);
    }

    public function enabled(Feature|string $feature, ?string $tenantId = null): bool
    {
        $key = $feature instanceof Feature ? $feature->value : $feature;

        return $this->forTenant($tenantId ?? $this->context()->id())[$key] ?? false;
    }

    /** @return array<string, bool> */
    public function forTenant(?string $tenantId): array
    {
        if ($tenantId === null) {
            throw MissingTenantContext::for(self::class);
        }

        return $this->cache[$tenantId] ??= $this->load($tenantId);
    }

    public function flush(): void
    {
        $this->cache = [];
    }

    /** @return array<string, bool> */
    private function load(string $tenantId): array
    {
        $planId = Tenant::query()->whereKey($tenantId)->value('plan_id');

        $features = DB::table('plan_features')
            ->where('plan_id', $planId)
            ->pluck('feature_key')
            ->mapWithKeys(fn (string $key) => [$key => true])
            ->all();

        $overrides = $this->context()->run($tenantId, fn () => DB::table('tenant_features')
            ->where('tenant_id', $tenantId)
            ->pluck('enabled', 'feature_key')
            ->all());

        foreach ($overrides as $key => $enabled) {
            $features[$key] = (bool) $enabled;
        }

        return $features;
    }
}
