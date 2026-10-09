<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Permission;
use App\Http\Controllers\Controller;
use App\Models\Outlet;
use App\Models\Shift;
use App\Models\User;
use App\Services\CashMovementService;
use App\Services\ShiftReportService;
use App\Services\ShiftService;
use App\Support\OutletFilter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class ShiftController extends Controller
{
    /** Shift terbuka di tablet ini (null jika belum dibuka). Ringkasan uang tidak ikut, agar hitung kas tetap "buta". */
    public function current(Request $request, ShiftService $shifts): JsonResponse
    {
        $shift = $shifts->current($request->attributes->get('device'));

        return response()->json(['data' => $shift ? $this->present($shift) : null]);
    }

    public function open(Request $request, ShiftService $shifts): JsonResponse
    {
        $data = $request->validate(['opening_cash' => ['required', 'integer', 'min:0', 'max:100000000']]);
        $shift = $shifts->open($request->attributes->get('device'), $request->user(), $data['opening_cash']);

        return response()->json(['data' => $this->present($shift)], 201);
    }

    /** Catatan kas keluar/masuk shift terbuka tablet ini + daftar kategori. */
    public function cashMovements(Request $request, ShiftService $shifts, CashMovementService $cash): JsonResponse
    {
        $shift = $shifts->current($request->attributes->get('device'));

        return response()->json([
            'data' => $shift ? $cash->forShift($shift->id) : [],
            'categories' => CashMovementService::categoryList(),
        ]);
    }

    public function recordCashMovement(Request $request, CashMovementService $cash): JsonResponse
    {
        $data = $request->validate([
            'id' => ['required', 'uuid'],
            'kind' => ['required', 'in:out,in'],
            'category' => ['required', 'string', 'max:20'],
            'amount' => ['required', 'integer', 'min:1', 'max:100000000'],
            'note' => ['nullable', 'string', 'max:120'],
        ]);
        $row = $cash->record($data, $request->user(), $request->attributes->get('device'));

        return response()->json(['data' => ['id' => $row->id, 'amount' => (int) $row->amount, 'kind' => $row->kind]], 201);
    }

    public function cancelCashMovement(Request $request, string $movement, CashMovementService $cash): JsonResponse
    {
        $data = $request->validate([
            'reason' => ['required', 'string', 'min:3', 'max:120'],
            'approval' => ['nullable', 'array:user_id,pin'],
            'approval.user_id' => ['required_with:approval', 'uuid'],
            'approval.pin' => ['required_with:approval', 'string', 'regex:/^\d{4,6}$/'],
        ]);
        $cash->cancel($movement, $data['reason'], $data['approval'] ?? null, $request->user(), $request->attributes->get('device'));

        return response()->json(['message' => 'Catatan kas dibatalkan.']);
    }

    /** Tutup shift tablet ini; respons memuat ringkasan + selisih untuk dicetak. */
    public function close(Request $request, ShiftService $shifts): JsonResponse
    {
        $data = $request->validate([
            'counted_cash' => ['required', 'integer', 'min:0', 'max:100000000'],
            'note' => ['nullable', 'string', 'max:255'],
        ]);
        $shift = $shifts->current($request->attributes->get('device'));
        abort_if($shift === null, 409, 'Tidak ada shift terbuka di tablet ini.');

        $closed = $shifts->close($shift, $request->user(), $data['counted_cash'], $data['note'] ?? null);
        app(ShiftReportService::class)->emailOwner($closed); // setelah respons; kasir tidak menunggu

        return response()->json(['data' => $this->present($closed, $shifts->summary($closed))]);
    }

    /** Teks laporan shift + tautan WhatsApp ke owner (bila nomornya ada). */
    public function report(Shift $shift, ShiftReportService $reports): JsonResponse
    {
        $text = $reports->text($shift);
        $phone = $reports->ownerWhatsApp();

        return response()->json(['data' => [
            'text' => $text,
            'whatsapp_url' => $phone ? 'https://wa.me/'.ltrim($phone, '+').'?text='.rawurlencode($text) : null,
        ]]);
    }

    /** Riwayat shift untuk owner (laporan kas). */
    public function index(Request $request, ShiftService $shifts): JsonResponse
    {
        abort_unless(Gate::allows(Permission::ReportsView->value), 403);
        $data = $request->validate(['per_page' => ['nullable', 'integer', 'min:1', 'max:50']]);

        $outlet = OutletFilter::resolve($request, default: null); // default: semua outlet
        $page = Shift::query()->when($outlet, fn ($q, $id) => $q->where('outlet_id', $id))
            ->latest('opened_at')->paginate($data['per_page'] ?? 20);

        return response()->json([
            'data' => collect($page->items())->map(fn (Shift $s) => $this->present($s, $shifts->summary($s))),
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage()],
        ]);
    }

    /** @param  array<string, mixed>|null  $summary */
    private function present(Shift $shift, ?array $summary = null): array
    {
        $names = User::query()->whereIn('id', array_filter([$shift->opened_by, $shift->closed_by]))->pluck('name', 'id');

        return [
            'id' => $shift->id,
            'outlet' => Outlet::query()->whereKey($shift->outlet_id)->value('name'),
            'opened_by' => $names[$shift->opened_by] ?? null,
            'opened_at' => $shift->opened_at->toIso8601String(),
            'opening_cash' => $shift->opening_cash,
            'closed_by' => $shift->closed_by ? ($names[$shift->closed_by] ?? null) : null,
            'closed_at' => $shift->closed_at?->toIso8601String(),
            'expected_cash' => $shift->expected_cash,
            'counted_cash' => $shift->counted_cash,
            'difference' => $shift->difference,
            'note' => $shift->note,
            'summary' => $summary,
        ];
    }
}
