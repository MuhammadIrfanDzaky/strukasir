<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Plan;
use App\Models\Tenant;
use App\Services\Payments\SubscriptionCheckout;
use App\Services\SubscriptionService;
use App\Support\PlanCatalog;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/** Paket usaha: status (sidebar & halaman Upgrade) dan permintaan upgrade oleh owner. */
class SubscriptionController extends Controller
{
    public function __construct(private readonly SubscriptionService $subscriptions) {}

    public function show(TenantContext $context): JsonResponse
    {
        return response()->json(['data' => $this->subscriptions->present(Tenant::query()->findOrFail($context->id()))]);
    }

    /** Owner: buat tagihan Mayar (QRIS) untuk paket & periode (harga dihitung server). */
    public function checkout(Request $request, TenantContext $context, SubscriptionCheckout $checkout): JsonResponse
    {
        $data = $request->validate([
            'plan' => ['required', 'string', Rule::exists('plans', 'code')->where('public', true)],
            'period' => ['required', Rule::in(array_keys(PlanCatalog::PERIODS))],
        ]);
        if (! $checkout->enabled()) {
            return response()->json(['message' => 'Pembayaran online belum tersedia. Hubungi tim Strukasir.'], 503);
        }
        $tenant = Tenant::query()->findOrFail($context->id());
        $plan = Plan::query()->where('code', $data['plan'])->firstOrFail();
        // Tetap dicatat sebagai permintaan (terlihat di halaman Upgrade bila QR belum dibayar).
        $this->subscriptions->request($tenant, $plan, $data['period']);
        try {
            $invoice = $checkout->create($tenant->refresh(), $plan, $data['period']);
        } catch (\RuntimeException $e) {
            report($e);

            return response()->json(['message' => 'Gagal membuat tagihan. Coba lagi sebentar lagi.'], 502);
        }

        return response()->json(['data' => SubscriptionCheckout::present($invoice)], 201);
    }

    /** Status tagihan (app memeriksa berkala); status dicocokkan ke Mayar selama masih menunggu. */
    public function invoice(string $invoice, TenantContext $context, SubscriptionCheckout $checkout): JsonResponse
    {
        $row = DB::table('subscription_invoices')->where('id', $invoice)->where('tenant_id', $context->id())->first();
        abort_if($row === null, 404);
        if ($checkout->enabled()) {
            $row = $checkout->sync($row);
        }

        return response()->json(['data' => SubscriptionCheckout::present($row)]);
    }

    public function request(Request $request, TenantContext $context): JsonResponse
    {
        $data = $request->validate([
            'plan' => ['required', 'string', Rule::exists('plans', 'code')->where('public', true)],
            'period' => ['required', Rule::in(array_keys(PlanCatalog::PERIODS))],
        ]);
        $tenant = Tenant::query()->findOrFail($context->id());
        $this->subscriptions->request($tenant, Plan::query()->where('code', $data['plan'])->firstOrFail(), $data['period']);

        return response()->json(['data' => $this->subscriptions->present($tenant->refresh())]);
    }
}
