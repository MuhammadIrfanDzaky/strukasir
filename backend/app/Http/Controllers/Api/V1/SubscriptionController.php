<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Plan;
use App\Models\Tenant;
use App\Services\SubscriptionService;
use App\Support\PlanCatalog;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Paket usaha: status (sidebar & halaman Upgrade) dan permintaan upgrade oleh owner. */
class SubscriptionController extends Controller
{
    public function __construct(private readonly SubscriptionService $subscriptions) {}

    public function show(TenantContext $context): JsonResponse
    {
        return response()->json(['data' => $this->subscriptions->present(Tenant::query()->findOrFail($context->id()))]);
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
