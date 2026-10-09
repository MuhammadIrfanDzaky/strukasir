<?php

namespace App\Services;

use App\Enums\Permission;
use App\Models\Device;
use App\Models\User;
use App\Support\Approval;
use App\Support\Audit;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

/**
 * Kas keluar / masuk di shift. Baris pembatalan memakai `kind` yang sama dengan nilai yang dibalik
 * di perhitungan (lihat net()), jadi laporan per kategori tetap benar.
 */
class CashMovementService
{
    /** Kategori → [label, dihitung sebagai biaya?]. "Setor ke owner" = uang pindah tangan, bukan biaya. */
    public const CATEGORIES = [
        'out' => [
            'ingredients' => ['Belanja bahan', true],
            'operational' => ['Operasional (gas, air, listrik)', true],
            'wages' => ['Gaji / upah harian', true],
            'withdrawal' => ['Setor ke owner', false],
            'other_out' => ['Lainnya', true],
        ],
        'in' => [
            'float' => ['Tambah modal / uang kecil', false],
            'other_in' => ['Lainnya', false],
        ],
    ];

    /** Jumlah bersih (pembatalan mengurangi) per jenis, untuk ringkasan shift. */
    public static function netSql(): string
    {
        return 'sum(case when reversal_of is null then amount else -amount end)';
    }

    /** @param  array{id: string, kind: string, category: string, amount: int, note?: ?string}  $data */
    public function record(array $data, User $user, Device $device): object
    {
        if (! isset(self::CATEGORIES[$data['kind']][$data['category']])) {
            throw ValidationException::withMessages(['category' => 'Kategori tidak sesuai jenis kas.']);
        }
        $existing = DB::table('cash_movements')->where('id', $data['id'])->first();
        if ($existing !== null) {
            if ((int) $existing->amount !== (int) $data['amount'] || $existing->kind !== $data['kind']) {
                throw new ConflictHttpException('ID kas sudah dipakai.');
            }

            return $existing; // kiriman ulang dari tablet
        }

        $shift = app(ShiftService::class)->requireOpen($device);
        if ($data['kind'] === 'out') {
            // Tidak boleh mengeluarkan lebih dari uang yang seharusnya ada di laci. Angkanya tidak
            // disebut: hitung kas saat tutup shift tetap "buta".
            if ($data['amount'] > app(ShiftService::class)->summary($shift)['expected_cash']) {
                throw ValidationException::withMessages(['amount' => 'Melebihi uang tunai yang seharusnya ada di laci.']);
            }
        }

        DB::table('cash_movements')->insert([
            'id' => $data['id'],
            'tenant_id' => $user->tenant_id,
            'shift_id' => $shift->id,
            'kind' => $data['kind'],
            'category' => $data['category'],
            'amount' => $data['amount'],
            'note' => $data['note'] ?? null,
            'created_by' => $user->id,
            'created_at' => now(),
        ]);
        Audit::record('cash.'.$data['kind'], null, after: [
            'category' => $data['category'], 'amount' => $data['amount'], 'note' => $data['note'] ?? null,
        ], user: $user, device: $device);

        return DB::table('cash_movements')->where('id', $data['id'])->first();
    }

    /** Batalkan catatan kas (salah input). Kasir butuh PIN owner; dicatat di shift yang sedang buka. */
    public function cancel(string $id, string $reason, ?array $approval, User $user, Device $device): void
    {
        $approver = Gate::forUser($user)->allows(Permission::OrderVoid->value)
            ? $user
            : Approval::verify($approval, Permission::OrderVoid);

        DB::transaction(function () use ($id, $reason, $user, $device, $approver) {
            $row = DB::table('cash_movements')->where('id', $id)->whereNull('reversal_of')->lockForUpdate()->first();
            if ($row === null) {
                throw ValidationException::withMessages(['id' => 'Catatan kas tidak ditemukan.']);
            }
            if (DB::table('cash_movements')->where('reversal_of', $id)->exists()) {
                throw new ConflictHttpException('Catatan ini sudah dibatalkan.');
            }
            $shift = app(ShiftService::class)->requireOpen($device);
            DB::table('cash_movements')->insert([
                'id' => (string) Str::uuid(),
                'tenant_id' => $user->tenant_id,
                'shift_id' => $shift->id,
                'kind' => $row->kind,
                'category' => $row->category,
                'amount' => $row->amount,
                'note' => mb_substr($reason, 0, 120),
                'reversal_of' => $id,
                'created_by' => $user->id,
                'created_at' => now(),
            ]);
            Audit::record('cash.cancelled', null, before: ['id' => $id, 'amount' => (int) $row->amount, 'kind' => $row->kind],
                after: ['reason' => $reason, 'approver_id' => $approver->id], user: $user, device: $device);
        });
    }

    /** @return list<array<string, mixed>> catatan kas satu shift (terbaru dulu) */
    public function forShift(string $shiftId): array
    {
        $rows = DB::table('cash_movements as m')
            ->leftJoin('users', 'users.id', '=', 'm.created_by')
            ->where('m.shift_id', $shiftId)
            ->orderByDesc('m.created_at')
            ->get(['m.*', 'users.name as user_name']);
        $cancelled = $rows->whereNotNull('reversal_of')->pluck('reversal_of')->all();

        return $rows->whereNull('reversal_of')->map(fn ($r) => [
            'id' => $r->id,
            'kind' => $r->kind,
            'category' => $r->category,
            'category_label' => self::CATEGORIES[$r->kind][$r->category][0] ?? $r->category,
            'amount' => (int) $r->amount,
            'note' => $r->note,
            'user' => $r->user_name,
            'cancelled' => in_array($r->id, $cancelled, true),
            'created_at' => Carbon::parse($r->created_at, 'UTC')->toIso8601String(),
        ])->values()->all();
    }

    /** @return list<array{kind: string, key: string, label: string, expense: bool}> */
    public static function categoryList(): array
    {
        $out = [];
        foreach (self::CATEGORIES as $kind => $cats) {
            foreach ($cats as $key => [$label, $expense]) {
                $out[] = ['kind' => $kind, 'key' => $key, 'label' => $label, 'expense' => $expense];
            }
        }

        return $out;
    }
}
