<?php

namespace App\Services;

use App\Models\Device;
use App\Models\Shift;
use App\Models\User;
use App\Support\Audit;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

/**
 * Shift kasir per tablet: modal awal → transaksi → hitung kas → tutup.
 * Kas seharusnya = modal + pembayaran tunai − refund tunai yang tercatat di shift ini.
 */
class ShiftService
{
    public function current(Device $device): ?Shift
    {
        return Shift::query()->where('device_id', $device->id)->whereNull('closed_at')->first();
    }

    public function open(Device $device, User $user, int $openingCash): Shift
    {
        if ($this->current($device)) {
            throw new ConflictHttpException('Masih ada shift terbuka di tablet ini. Tutup dulu.');
        }

        $shift = new Shift;
        $shift->forceFill([
            'device_id' => $device->id,
            'opened_by' => $user->id,
            'opened_at' => now(),
            'opening_cash' => $openingCash,
        ])->save();

        Audit::record('shift.opened', $shift, after: ['opening_cash' => $openingCash], user: $user, device: $device);

        return $shift;
    }

    /**
     * Tutup shift dengan kas yang dihitung kasir (blind count: kasir tidak melihat angka sistem dulu).
     */
    public function close(Shift $shift, User $user, int $countedCash, ?string $note): Shift
    {
        return DB::transaction(function () use ($shift, $user, $countedCash, $note) {
            $shift = Shift::query()->lockForUpdate()->findOrFail($shift->id);
            if ($shift->closed_at !== null) {
                throw new ConflictHttpException('Shift ini sudah ditutup.');
            }

            $expected = $this->summary($shift)['expected_cash'];
            $shift->forceFill([
                'closed_by' => $user->id,
                'closed_at' => now(),
                'expected_cash' => $expected,
                'counted_cash' => $countedCash,
                'difference' => $countedCash - $expected,
                'note' => $note,
            ])->save();

            Audit::record('shift.closed', $shift, after: [
                'expected_cash' => $expected,
                'counted_cash' => $countedCash,
                'difference' => $countedCash - $expected,
            ], user: $user);

            return $shift;
        });
    }

    /**
     * Ringkasan uang dalam shift, dihitung dari tabel pembayaran (bukan order) agar split payment,
     * open bill dari shift lain, dan refund tercatat di shift tempat uang benar-benar bergerak.
     *
     * @return array{opening_cash: int, cash_in: int, cash_refund: int, expected_cash: int,
     *     by_method: array<string, int>, paid_orders: int, refunds: int}
     */
    public function summary(Shift $shift): array
    {
        $rows = DB::table('payments')
            ->where('shift_id', $shift->id)
            ->selectRaw('method, kind, sum(amount) as total, count(distinct order_id) as orders')
            ->groupBy('method', 'kind')
            ->get();

        $sum = fn (string $kind, ?string $method = null) => (int) $rows
            ->where('kind', $kind)
            ->when($method, fn ($c) => $c->where('method', $method))
            ->sum('total');

        $byMethod = [];
        foreach (['cash', 'debit', 'qris'] as $method) {
            $byMethod[$method] = $sum('payment', $method) - $sum('refund', $method);
        }

        $cashIn = $sum('payment', 'cash');
        $cashRefund = $sum('refund', 'cash');

        return [
            'opening_cash' => $shift->opening_cash,
            'cash_in' => $cashIn,
            'cash_refund' => $cashRefund,
            'expected_cash' => $shift->opening_cash + $cashIn - $cashRefund,
            'by_method' => $byMethod,
            'paid_orders' => (int) DB::table('payments')->where('shift_id', $shift->id)
                ->where('kind', 'payment')->distinct()->count('order_id'),
            'refunds' => (int) DB::table('payments')->where('shift_id', $shift->id)
                ->where('kind', 'refund')->distinct()->count('order_id'),
        ];
    }

    /** Dipakai saat bayar/refund: transaksi uang wajib di dalam shift terbuka. */
    public function requireOpen(Device $device): Shift
    {
        return $this->current($device)
            ?? throw ValidationException::withMessages(['shift' => 'Buka shift terlebih dahulu.']);
    }
}
