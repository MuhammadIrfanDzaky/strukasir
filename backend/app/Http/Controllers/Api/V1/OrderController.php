<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Feature;
use App\Http\Controllers\Controller;
use App\Http\Requests\PayOrderRequest;
use App\Http\Requests\UpsertOrderRequest;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use App\Services\OrderService;
use App\Support\Tenancy\FeatureGate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Str;

class OrderController extends Controller
{
    /** Daftar order, mis. `?status=open` untuk "struk belum dibayar". Selalu berhalaman (SEC-26). */
    public function index(Request $request, FeatureGate $features): AnonymousResourceCollection
    {
        $validated = $request->validate([
            'status' => ['nullable', 'in:open,paid,void'],
            'date' => ['nullable', 'date_format:Y-m-d'], // hari bisnis
            'q' => ['nullable', 'string', 'max:30'], // cari nomor order / nama pelanggan
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
        ]);

        if (($validated['status'] ?? null) === 'open' && ! $features->enabled(Feature::OpenBill)) {
            abort(403, 'Fitur open bill tidak aktif untuk kedai ini.');
        }

        $orders = Order::query()
            ->when($validated['status'] ?? null, fn ($q, $status) => $q->where('status', $status))
            ->when($validated['date'] ?? null, fn ($q, $date) => $q->where('business_date', $date))
            ->when($validated['q'] ?? null, fn ($q, $term) => $q->where(fn ($w) => $w
                ->where('number', 'ilike', '%'.addcslashes($term, '%_\\').'%')
                ->orWhere('customer_label', 'ilike', '%'.addcslashes($term, '%_\\').'%')))
            ->latest()
            // Satu query per relasi untuk seluruh halaman (bukan per order).
            ->with(['items.modifiers', 'payments', 'cashier:id,name', 'customer:id,code,name,anonymized_at'])
            ->paginate($validated['per_page'] ?? 20);

        return OrderResource::collection($orders);
    }

    public function show(string $order): OrderResource
    {
        return new OrderResource(Order::query()->findOrFail($this->uuid($order)));
    }

    /** Selalu 200 (baru maupun kiriman ulang) — tablet cukup tahu "tersimpan". */
    public function upsert(UpsertOrderRequest $request, string $order, OrderService $orders): JsonResponse
    {
        return (new OrderResource($orders->upsert(
            $this->uuid($order),
            $request->validated(),
            $request->user(),
            $request->attributes->get('device'),
            $request->attributes->get('tenant'),
        )))->response()->setStatusCode(200);
    }

    public function pay(PayOrderRequest $request, string $order, OrderService $orders): OrderResource
    {
        return new OrderResource($orders->pay(
            $this->uuid($order),
            $request->validated('payments'),
            (int) $request->validated('expected_total'),
            $request->user(),
            $request->attributes->get('device'),
        ));
    }

    public function void(Request $request, string $order, OrderService $orders): OrderResource
    {
        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:255'],
            'approval' => ['nullable', 'array:user_id,pin'],
            'approval.user_id' => ['required_with:approval', 'uuid'],
            'approval.pin' => ['required_with:approval', 'string', 'regex:/^\d{4,6}$/'],
        ]);

        return new OrderResource($orders->void(
            $this->uuid($order),
            $data['reason'],
            $data['approval'] ?? null,
            $request->user(),
            $request->attributes->get('device'),
        ));
    }

    private function uuid(string $value): string
    {
        abort_unless(Str::isUuid($value), 404);

        return strtolower($value);
    }
}
