<?php

namespace App\Services;

use App\Enums\Feature;
use App\Enums\Permission;
use App\Models\CreditRepayment;
use App\Models\Customer;
use App\Models\Device;
use App\Models\Order;
use App\Models\TenantSetting;
use App\Models\User;
use App\Support\Approval;
use App\Support\Audit;
use App\Support\Tenancy\FeatureGate;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

/**
 * Kasbon / piutang member. Piutang dihitung dari dua buku append-only (payments metode `credit`
 * dan credit_repayments), jadi tidak ada saldo tersimpan yang bisa melenceng.
 */
class CreditService
{
    public function enabled(): bool
    {
        return app(FeatureGate::class)->enabled(Feature::CustomerCredit);
    }

    /** Piutang per pelanggan (customer_id, credit_balance) — untuk join ke daftar pelanggan. */
    public static function balanceQuery(): Builder
    {
        $charged = DB::table('payments')
            ->join('orders', 'orders.id', '=', 'payments.order_id')
            ->where('payments.method', 'credit')
            ->selectRaw("orders.customer_id, case when payments.kind = 'payment' then payments.amount else -payments.amount end as delta");
        $repaid = DB::table('credit_repayments')
            ->selectRaw("customer_id, case when kind = 'repayment' then -amount else amount end as delta");

        return DB::query()->fromSub($charged->unionAll($repaid), 'c')
            ->whereNotNull('customer_id')
            ->groupBy('customer_id')
            ->selectRaw('customer_id, sum(delta) as credit_balance');
    }

    public function balance(string $customerId): int
    {
        return (int) DB::query()->fromSub(self::balanceQuery(), 'b')->where('customer_id', $customerId)->value('credit_balance');
    }

    /** Batas kasbon efektif: per pelanggan, atau default kedai; null = tanpa batas. */
    public function limitFor(Customer $customer): ?int
    {
        if ($customer->credit_limit !== null) {
            return (int) $customer->credit_limit;
        }
        $default = TenantSetting::query()->value('credit_default_limit');

        return $default === null ? null : (int) $default;
    }

    /**
     * Sebelum bayar dengan kasbon (di luar transaksi agar PIN salah tetap tercatat): fitur aktif,
     * order bermember, dan piutang baru tidak melewati batas — kalau lewat, wajib persetujuan owner.
     */
    public function authorizeCharge(Order $order, int $amount, User $cashier, ?array $approval): ?User
    {
        if ($amount === 0) {
            return null;
        }
        $fail = fn (string $m) => throw ValidationException::withMessages(['payments' => $m]);
        $this->enabled() || $fail('Fitur kasbon tidak aktif untuk kedai ini.');
        $customer = $order->customer_id ? Customer::query()->find($order->customer_id) : null;
        if ($customer === null || $customer->isAnonymized()) {
            $fail('Kasbon hanya untuk member. Pilih member dulu.');
        }

        $limit = $this->limitFor($customer);
        $after = $this->balance($customer->id) + $amount;
        if ($limit === null || $after <= $limit || Gate::forUser($cashier)->allows(Permission::CreditOverLimit->value)) {
            return null;
        }
        if ($approval === null) {
            throw ValidationException::withMessages([
                'approval' => 'Kasbon '.$customer->name.' akan menjadi Rp'.number_format($after, 0, ',', '.')
                    .', melewati batas Rp'.number_format($limit, 0, ',', '.').'. Perlu PIN owner.',
            ]);
        }

        return Approval::verify($approval, Permission::CreditOverLimit);
    }

    /**
     * Catat pelunasan di shift terbuka. Idempotent per ID dari tablet.
     *
     * @param  array{id: string, method: string, amount: int, tendered?: ?int, note?: ?string}  $data
     */
    public function repay(Customer $customer, array $data, User $user, Device $device): CreditRepayment
    {
        $existing = CreditRepayment::query()->find($data['id']);
        if ($existing !== null) {
            if ($existing->customer_id !== $customer->id || $existing->amount !== (int) $data['amount']) {
                throw new ConflictHttpException('ID pelunasan sudah dipakai.');
            }

            return $existing;
        }
        if ($data['method'] !== 'cash' && isset($data['tendered'])) {
            throw ValidationException::withMessages(['tendered' => 'Uang diterima hanya untuk tunai.']);
        }
        $tendered = $data['method'] === 'cash' ? ($data['tendered'] ?? $data['amount']) : null;
        if ($tendered !== null && $tendered < $data['amount']) {
            throw ValidationException::withMessages(['tendered' => 'Uang diterima kurang dari nominal.']);
        }

        $repayment = DB::transaction(function () use ($customer, $data, $user, $device, $tendered) {
            Customer::query()->lockForUpdate()->findOrFail($customer->id); // pelunasan paralel tidak melebihi piutang
            $owed = $this->balance($customer->id);
            if ($data['amount'] > $owed) {
                throw ValidationException::withMessages(['amount' => 'Melebihi sisa kasbon (Rp'.number_format(max(0, $owed), 0, ',', '.').').']);
            }
            $shift = app(ShiftService::class)->requireOpen($device);

            return CreditRepayment::create([
                'id' => $data['id'],
                'customer_id' => $customer->id,
                'shift_id' => $shift->id,
                'kind' => 'repayment',
                'method' => $data['method'],
                'amount' => $data['amount'],
                'tendered' => $tendered,
                'change' => $tendered === null ? 0 : $tendered - $data['amount'],
                'note' => $data['note'] ?? null,
                'confirmed_by' => $user->id,
            ]);
        });
        Audit::record('credit.repaid', $customer, after: ['code' => $customer->code, 'amount' => $repayment->amount, 'method' => $repayment->method], user: $user, device: $device);

        return $repayment;
    }

    /** Owner membatalkan pelunasan yang salah catat: baris pembatalan di shift terbuka (uang keluar). */
    public function reverse(CreditRepayment $repayment, string $reason, User $user, Device $device): CreditRepayment
    {
        if ($repayment->kind !== 'repayment') {
            throw ValidationException::withMessages(['repayment' => 'Hanya pelunasan yang bisa dibatalkan.']);
        }
        $reversal = DB::transaction(function () use ($repayment, $reason, $user, $device) {
            if (CreditRepayment::query()->where('reversal_of', $repayment->id)->exists()) {
                throw new ConflictHttpException('Pelunasan ini sudah dibatalkan.');
            }
            $shift = app(ShiftService::class)->requireOpen($device);

            return CreditRepayment::create([
                'id' => (string) Str::uuid(),
                'customer_id' => $repayment->customer_id,
                'shift_id' => $shift->id,
                'kind' => 'reversal',
                'reversal_of' => $repayment->id,
                'method' => $repayment->method,
                'amount' => $repayment->amount,
                'note' => mb_substr($reason, 0, 120),
                'confirmed_by' => $user->id,
            ]);
        });
        Audit::record('credit.repayment_reversed', $repayment->customer, after: ['amount' => $repayment->amount, 'reason' => $reason], user: $user, device: $device);

        return $reversal;
    }

    /**
     * Riwayat kasbon & pelunasan pelanggan (terbaru dulu, maks. 50).
     *
     * @return list<array<string, mixed>>
     */
    public function history(Customer $customer): array
    {
        $charges = DB::table('payments')
            ->join('orders', 'orders.id', '=', 'payments.order_id')
            ->where('orders.customer_id', $customer->id)
            ->where('payments.method', 'credit')
            ->selectRaw("payments.id, case when payments.kind = 'payment' then 'charge' else 'charge_void' end as kind, payments.amount, null as method, orders.number, payments.created_at, null as reversed");
        $repayments = DB::table('credit_repayments as r')
            ->where('r.customer_id', $customer->id)
            ->selectRaw("r.id, case when r.kind = 'repayment' then 'repayment' else 'reversal' end as kind, r.amount, r.method, r.note as number, r.created_at, "
                .'exists(select 1 from credit_repayments x where x.reversal_of = r.id) as reversed');

        return DB::query()->fromSub($charges->unionAll($repayments), 'h')
            ->orderByDesc('created_at')->limit(50)->get()
            ->map(fn ($r) => [
                'id' => $r->id,
                'kind' => $r->kind,
                'amount' => (int) $r->amount,
                'method' => $r->method,
                'label' => $r->number,
                'reversed' => (bool) $r->reversed,
                'created_at' => Carbon::parse($r->created_at, 'UTC')->toIso8601String(),
            ])->all();
    }
}
