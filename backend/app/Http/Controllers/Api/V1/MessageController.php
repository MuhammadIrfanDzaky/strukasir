<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Permission;
use App\Http\Controllers\Controller;
use App\Models\Customer;
use App\Models\Order;
use App\Services\MessagingService;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Pesan WhatsApp ke member (fitur `customer_messaging`). Kasir hanya boleh mengirim struk digital;
 * template lain & daftar siap-kirim untuk owner.
 */
class MessageController extends Controller
{
    public function __construct(private readonly MessagingService $messaging) {}

    /** Siapkan tautan wa.me untuk satu pelanggan (dicatat di riwayat pesan). */
    public function prepare(Request $request, Customer $customer): JsonResponse
    {
        $this->guardFeature();
        abort_if($customer->isAnonymized(), 404);
        $data = $request->validate([
            'template' => ['required', Rule::in(array_keys(MessagingService::TEMPLATES))],
            'order_id' => ['nullable', 'uuid'],
        ]);
        if ($data['template'] !== 'receipt') {
            abort_unless($request->user()->can(Permission::CustomersManage->value), 403, 'Hanya owner yang bisa mengirim pesan ini.');
        }
        $order = isset($data['order_id']) ? Order::query()->find($data['order_id']) : null;

        return response()->json(['data' => $this->messaging->prepare($customer, $data['template'], $order, $request->user())]);
    }

    /** Daftar siap-kirim: ulang tahun minggu ini, pelanggan menghilang, berkasbon. */
    public function audience(Request $request): JsonResponse
    {
        $this->guardFeature();
        $data = $request->validate(['template' => ['required', Rule::in(MessagingService::AUDIENCES)]]);

        return response()->json(['data' => $this->messaging->audience($data['template'])]);
    }

    public function templates(): JsonResponse
    {
        $this->guardFeature();

        return response()->json(['data' => $this->present()]);
    }

    public function saveTemplates(Request $request): JsonResponse
    {
        $this->guardFeature();
        $keys = array_keys(MessagingService::TEMPLATES);
        $data = $request->validate([
            'templates' => ['required', 'array:'.implode(',', $keys)],
            'templates.*' => ['nullable', 'string', 'max:1000'],
        ]);
        $this->messaging->saveTemplates($data['templates']);
        Audit::record('messages.templates_updated', null, after: ['keys' => array_keys($data['templates'])]);

        return response()->json(['data' => $this->present()]);
    }

    /** @return array<string, mixed> */
    private function present(): array
    {
        $bodies = $this->messaging->templates();

        return [
            'templates' => collect(MessagingService::TEMPLATES)->map(fn ($t, $key) => [
                'key' => $key,
                'title' => $t[0],
                'body' => $bodies[$key],
                'default' => $t[1],
            ])->values(),
            'placeholders' => MessagingService::PLACEHOLDERS,
        ];
    }

    private function guardFeature(): void
    {
        abort_unless($this->messaging->enabled(), 403, 'Fitur pesan WhatsApp tidak aktif untuk kedai ini.');
    }
}
