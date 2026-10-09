<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Permission;
use App\Http\Controllers\Controller;
use App\Http\Requests\CustomerRequest;
use App\Models\Customer;
use App\Services\CustomerService;
use App\Support\PhoneNumber;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * Pelanggan / member (fitur `customers`).
 * Kasir (`customers.view`): cari & daftarkan pelanggan di layar kasir; no HP tampil tersamar,
 * tanpa total belanja & tanggal lahir. Owner (`customers.manage`): data lengkap, ubah, hapus data.
 */
class CustomerController extends Controller
{
    public function __construct(private readonly CustomerService $customers) {}

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'q' => ['nullable', 'string', 'max:80'],
            'segment' => ['nullable', Rule::in(CustomerService::SEGMENTS)],
            'sort' => ['nullable', Rule::in(['name', 'recent', 'top', 'newest'])],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:50'],
            'with_counts' => ['sometimes', 'boolean'],
        ]);
        $full = $this->full($request);

        $page = $this->customers
            ->search($this->customers->withStats(), $data['q'] ?? null, $data['segment'] ?? null, $data['sort'] ?? 'name')
            ->paginate($data['per_page'] ?? 20);

        return response()->json([
            'data' => collect($page->items())->map(fn (Customer $c) => $this->present($c, $full)),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
                'phone_required' => $this->customers->phoneRequired(),
                ...($full && ($data['with_counts'] ?? false) ? ['segments' => $this->customers->segmentCounts()] : []),
            ],
        ]);
    }

    public function store(CustomerRequest $request): JsonResponse
    {
        $customer = $this->customers->create($request->validated());

        return response()->json(['data' => $this->present($this->reload($customer), $this->full($request))], 201);
    }

    public function show(Customer $customer): JsonResponse
    {
        abort_if($customer->isAnonymized(), 404);

        return response()->json(['data' => [
            ...$this->present($this->reload($customer), true),
            ...$this->customers->history($customer),
        ]]);
    }

    public function update(CustomerRequest $request, Customer $customer): JsonResponse
    {
        abort_if($customer->isAnonymized(), 404);
        $this->customers->update($customer, $request->validated());

        return response()->json(['data' => $this->present($this->reload($customer), true)]);
    }

    public function anonymize(Customer $customer): JsonResponse
    {
        abort_if($customer->isAnonymized(), 404);
        $this->customers->anonymize($customer);

        return response()->json(['message' => 'Data pribadi pelanggan sudah dihapus.']);
    }

    private function full(Request $request): bool
    {
        return (bool) $request->user()?->can(Permission::CustomersManage->value);
    }

    private function reload(Customer $customer): Customer
    {
        return $this->customers->withStats()->whereKey($customer->id)->firstOrFail();
    }

    /** Kolom agregat (bukan atribut ber-cast) dari withStats(); disimpan UTC. */
    private function iso(?string $timestamp): ?string
    {
        return $timestamp === null ? null : Carbon::parse($timestamp, 'UTC')->toIso8601String();
    }

    /** @return array<string, mixed> */
    private function present(Customer $c, bool $full): array
    {
        return [
            'id' => $c->id,
            'code' => $c->code,
            'name' => $c->name,
            'phone' => $full ? $c->phone : PhoneNumber::mask($c->phone),
            'note' => $c->note,
            'visits' => (int) $c->visits,
            'last_visit_at' => $this->iso($c->last_visit_at),
            ...($full ? [
                'birth_date' => $c->birth_date?->toDateString(),
                'total_spent' => (int) $c->total_spent,
                'first_visit_at' => $this->iso($c->first_visit_at),
                'created_at' => $c->created_at->toIso8601String(),
            ] : []),
        ];
    }
}
