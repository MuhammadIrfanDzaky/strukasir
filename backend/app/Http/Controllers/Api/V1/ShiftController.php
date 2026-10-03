<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Permission;
use App\Http\Controllers\Controller;
use App\Models\Shift;
use App\Models\User;
use App\Services\ShiftService;
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

        return response()->json(['data' => $this->present($closed, $shifts->summary($closed))]);
    }

    /** Riwayat shift untuk owner (laporan kas). */
    public function index(Request $request, ShiftService $shifts): JsonResponse
    {
        abort_unless(Gate::allows(Permission::ReportsView->value), 403);
        $data = $request->validate(['per_page' => ['nullable', 'integer', 'min:1', 'max:50']]);

        $page = Shift::query()->latest('opened_at')->paginate($data['per_page'] ?? 20);

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
