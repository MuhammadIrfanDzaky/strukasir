<?php

namespace App\Http\Middleware;

use App\Models\Tenant;
use App\Support\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Transaksi baru (simpan/bayar order, buka shift) hanya saat paket masih berlaku. Data, laporan,
 * pengaturan & halaman Upgrade tetap bisa dibuka setelah masa coba / langganan habis.
 */
class EnsurePlanActive
{
    public function handle(Request $request, Closure $next): Response
    {
        $tenant = Tenant::query()->find(app(TenantContext::class)->id());
        if ($tenant?->planExpired()) {
            return response()->json([
                'message' => $tenant->plan_status === 'active'
                    ? 'Masa langganan sudah habis. Perpanjang di menu Upgrade paket untuk lanjut berjualan.'
                    : 'Masa coba sudah habis. Pilih paket di menu Upgrade paket untuk lanjut berjualan.',
                'code' => 'plan_expired',
            ], 402);
        }

        return $next($request);
    }
}
