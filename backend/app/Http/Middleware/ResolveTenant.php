<?php

namespace App\Http\Middleware;

use App\Models\Device;
use App\Models\Tenant;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Menetapkan tenant aktif dari token yang terautentikasi — satu-satunya sumber tenant.
 *
 * Pemakaian: `tenant:device` (token tablet, hanya untuk daftar staf & login PIN) atau
 * `tenant:user` (token user hasil login PIN, untuk semua operasi lain).
 */
class ResolveTenant
{
    public function __construct(private readonly TenantContext $context) {}

    public function handle(Request $request, Closure $next, string $tokenType): Response
    {
        $actor = $request->user();
        $token = $actor?->currentAccessToken();

        $device = match ($tokenType) {
            'device' => $actor instanceof Device && $token?->can('device') ? $actor : null,
            'user' => $actor instanceof User && $token?->can('user') ? $token->device : null,
            default => null,
        };

        if ($device === null || $device->isRevoked()
            || ($actor instanceof User && (! $actor->active || $actor->tenant_id !== $device->tenant_id))) {
            abort(401, 'Sesi tidak valid. Silakan login ulang.');
        }

        $tenant = Tenant::find($device->tenant_id);
        if (! $tenant?->isActive()) {
            abort(403, 'Akun kedai tidak aktif.');
        }

        $this->context->set($tenant->id);
        $request->attributes->set('device', $device);
        $request->attributes->set('tenant', $tenant);

        if ($device->last_seen_at === null || $device->last_seen_at->lt(now()->subMinute())) {
            $device->forceFill(['last_seen_at' => now()])->saveQuietly();
        }

        return $next($request);
    }

    public function terminate(): void
    {
        $this->context->clear();
    }
}
