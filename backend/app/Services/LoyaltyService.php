<?php

namespace App\Services;

use App\Enums\Feature;
use App\Models\Customer;
use App\Models\LoyaltyEntry;
use App\Models\LoyaltyProgram;
use App\Models\LoyaltyReward;
use App\Models\Order;
use App\Models\User;
use App\Support\Audit;
use App\Support\Tenancy\FeatureGate;
use Carbon\CarbonInterface;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Program loyalitas: hitung stempel/poin dari order lunas, tukar hadiah, batalkan saat void,
 * hangus bila tidak ada transaksi N bulan, dan penyesuaian manual owner.
 *
 * Hadiah tidak menambah aturan harga baru: "gratis produk" = diskon item sebesar harga dasar 1 porsi
 * produk itu, "potongan Rp/%" = diskon order. Dengan begitu mesin harga & fixture app tetap sama.
 *
 * Hangus dihitung saat dibaca (tanpa cron): saldo tampil 0 bila aktivitas terakhir lebih lama dari
 * masa berlaku, lalu baris "hangus" dicatat saat pelanggan itu bertransaksi lagi.
 */
class LoyaltyService
{
    /** Program yang sedang berjalan (fitur aktif & program dinyalakan owner). */
    public function activeProgram(): ?LoyaltyProgram
    {
        // FeatureGate diambil saat dipakai (scoped per request), bukan disimpan di objek ini.
        if (! app(FeatureGate::class)->enabled(Feature::Loyalty)) {
            return null;
        }
        $program = LoyaltyProgram::query()->first();

        return $program?->active ? $program : null;
    }

    public function program(): ?LoyaltyProgram
    {
        return LoyaltyProgram::query()->first();
    }

    /**
     * Saldo efektif pelanggan (sudah memperhitungkan hangus).
     *
     * @return array{balance: int, last_activity_at: ?CarbonInterface, expires_at: ?CarbonInterface}
     */
    public function balance(string $customerId, ?LoyaltyProgram $program = null): array
    {
        $row = LoyaltyEntry::query()->where('customer_id', $customerId)
            ->selectRaw('coalesce(sum(units), 0) as balance, max(created_at) as last_at')->first();

        return self::effective((int) $row->balance, $row->last_at, $program ?? $this->program());
    }

    /**
     * @return array{balance: int, last_activity_at: ?CarbonInterface, expires_at: ?CarbonInterface}
     */
    public static function effective(int $balance, ?string $lastAt, ?LoyaltyProgram $program): array
    {
        $last = $lastAt === null ? null : Carbon::parse($lastAt, 'UTC');
        $expiresAt = $last !== null && $program?->expiry_months ? $last->copy()->addMonths($program->expiry_months) : null;
        $expired = $expiresAt !== null && $expiresAt->isPast() && $balance > 0;

        return [
            'balance' => $expired ? 0 : $balance,
            'last_activity_at' => $last,
            'expires_at' => $balance > 0 && ! $expired ? $expiresAt : null,
        ];
    }

    /**
     * Hadiah yang diminta kasir untuk order terbuka: aktif, member tertaut, saldo cukup, dan
     * (gratis produk) barisnya ada. Mengembalikan data untuk diterapkan sebagai diskon.
     *
     * @param  array{id: string, item_id?: ?string}|null  $request
     * @param  list<array<string, mixed>>  $lines  baris tervalidasi OrderService
     * @return array{reward: LoyaltyReward, line_index: ?int}|null
     */
    public function resolveReward(?array $request, ?Customer $customer, array $lines, ?Order $existing): ?array
    {
        if ($request === null) {
            return null;
        }
        $fail = fn (string $message) => throw ValidationException::withMessages(['reward' => $message]);

        $program = $this->activeProgram() ?? $fail('Program loyalitas tidak aktif.');
        $customer ?? $fail('Pilih member dulu untuk menukar hadiah.');
        $reward = LoyaltyReward::query()->find($request['id']);
        // Hadiah yang sudah tersimpan di open bill tetap berlaku walau owner menonaktifkannya kemudian.
        if ($reward === null || (! $reward->active && $existing?->reward_id !== $reward->id)) {
            $fail('Hadiah tidak tersedia.');
        }

        $balance = $this->balance($customer->id, $program)['balance'];
        if ($balance < $reward->cost) {
            $fail("Saldo {$program->unit()} tidak cukup ({$balance} dari {$reward->cost}).");
        }

        $lineIndex = null;
        if ($reward->type === 'free_product') {
            foreach ($lines as $i => $line) {
                if ($line['id'] === ($request['item_id'] ?? null) && $line['product']->id === $reward->product_id) {
                    $lineIndex = $i;
                }
            }
            $lineIndex ?? $fail('Tambahkan produk hadiah ke keranjang dulu.');
        }

        return ['reward' => $reward, 'line_index' => $lineIndex];
    }

    /**
     * Setelah order dibayar (di dalam transaksi bayar): tukar hadiah (saldo dicek ulang dengan kunci,
     * supaya dua open bill tidak memakai stempel yang sama), lalu catat stempel/poin yang didapat.
     *
     * @return array{earned: int, redeemed: int}
     */
    public function onPaid(Order $order, User $cashier): array
    {
        if ($order->customer_id === null) {
            return ['earned' => 0, 'redeemed' => 0];
        }
        $customer = Customer::query()->lockForUpdate()->find($order->customer_id);
        if ($customer === null || $customer->isAnonymized()) {
            return ['earned' => 0, 'redeemed' => 0];
        }
        $program = $this->program();
        $this->settleExpiry($customer, $program, $cashier);

        $redeemed = 0;
        if ($order->reward_id !== null) {
            $balance = $this->balance($customer->id, $program)['balance'];
            if ($balance < $order->reward_cost) {
                throw ValidationException::withMessages([
                    'reward' => 'Saldo stempel/poin member tidak cukup lagi untuk hadiah ini. Lepas hadiah, simpan, lalu bayar lagi.',
                ]);
            }
            $this->entry($customer, 'redeem', -$order->reward_cost, $cashier, $order, $order->reward_id, $order->reward_name);
            $redeemed = $order->reward_cost;
        }

        $earned = 0;
        $active = $this->activeProgram();
        if ($active !== null) {
            // Pengali tingkat member (mis. Gold 2×) dari salinan di order.
            $earned = $this->earnFor($order, $active) * max(1, (int) $order->tier_multiplier);
            if ($earned > 0) {
                $this->entry($customer, 'earn', $earned, $cashier, $order);
            }
        }

        return ['earned' => $earned, 'redeemed' => $redeemed];
    }

    /** Void order lunas: semua stempel/poin dari order itu dibatalkan (hadiah dikembalikan). */
    public function onVoid(Order $order, User $user): void
    {
        $entries = LoyaltyEntry::query()->where('order_id', $order->id)->whereIn('kind', ['earn', 'redeem'])->get();
        if ($entries->isEmpty() || LoyaltyEntry::query()->where('order_id', $order->id)->where('kind', 'reverse')->exists()) {
            return;
        }
        $customer = Customer::query()->lockForUpdate()->findOrFail($order->customer_id);
        foreach ($entries as $e) {
            $this->entry($customer, 'reverse', -$e->units, $user, $order, $e->reward_id, 'Void '.$order->number);
        }
    }

    /** Penyesuaian manual owner (mis. pindahan kartu stempel kertas). Alasan wajib, tercatat di audit. */
    public function adjust(Customer $customer, int $units, string $note, User $user): int
    {
        return DB::transaction(function () use ($customer, $units, $note, $user) {
            $locked = Customer::query()->lockForUpdate()->findOrFail($customer->id);
            $program = $this->program();
            $this->settleExpiry($locked, $program, $user);
            $balance = $this->balance($locked->id, $program)['balance'];
            if ($balance + $units < 0) {
                throw ValidationException::withMessages(['units' => "Saldo tidak boleh minus (saldo sekarang {$balance})."]);
            }
            $this->entry($locked, 'adjust', $units, $user, note: $note);
            Audit::record('loyalty.adjusted', $locked, after: ['code' => $locked->code, 'units' => $units, 'note' => $note]);

            return $balance + $units;
        });
    }

    /**
     * Stempel/poin untuk order lunas.
     * - per_item: jumlah qty produk yang ikut (semua / kategori terpilih), 1 porsi hadiah gratis tidak dihitung;
     * - per_order: 1 bila total ≥ minimal belanja;
     * - per_amount: 1 poin per kelipatan Rp dari total bayar.
     */
    public function earnFor(Order $order, LoyaltyProgram $program): int
    {
        return match ($program->earn_mode) {
            'per_order' => $order->grand_total >= (int) $program->earn_min_order ? 1 : 0,
            'per_amount' => $program->earn_per_amount > 0 ? intdiv($order->grand_total, $program->earn_per_amount) : 0,
            default => $this->eligibleQty($order, $program),
        };
    }

    private function eligibleQty(Order $order, LoyaltyProgram $program): int
    {
        $categories = $program->category_ids ?: [];
        $items = DB::table('order_items')
            ->leftJoin('products', 'products.id', '=', 'order_items.product_id')
            ->where('order_items.order_id', $order->id)
            ->when($categories !== [], fn ($q) => $q->whereIn('products.category_id', $categories))
            ->get(['order_items.id', 'order_items.qty']);

        $qty = (int) $items->sum('qty');
        if ($order->reward_item_id !== null && $items->contains('id', $order->reward_item_id)) {
            $qty--; // porsi gratis tidak menghasilkan stempel
        }

        return max(0, $qty);
    }

    /** Catat baris "hangus" bila saldo lama sudah lewat masa berlaku. */
    private function settleExpiry(Customer $customer, ?LoyaltyProgram $program, User $user): void
    {
        if (! $program?->expiry_months) {
            return;
        }
        $row = LoyaltyEntry::query()->where('customer_id', $customer->id)
            ->selectRaw('coalesce(sum(units), 0) as balance, max(created_at) as last_at')->first();
        $raw = (int) $row->balance;
        if ($raw > 0 && self::effective($raw, $row->last_at, $program)['balance'] === 0) {
            $this->entry($customer, 'expire', -$raw, $user, note: "Tidak ada transaksi {$program->expiry_months} bulan");
        }
    }

    private function entry(Customer $customer, string $kind, int $units, User $user, ?Order $order = null, ?string $rewardId = null, ?string $note = null): void
    {
        LoyaltyEntry::create([
            'customer_id' => $customer->id,
            'order_id' => $order?->id,
            'kind' => $kind,
            'units' => $units,
            'reward_id' => $rewardId,
            'note' => $note === null ? null : mb_substr($note, 0, 120),
            'user_id' => $user->id,
        ]);
    }

    /**
     * Program + hadiah aktif untuk tablet (bagian GET /menu); null bila tidak berjalan.
     *
     * @return array<string, mixed>|null
     */
    public function presentForMenu(): ?array
    {
        $program = $this->activeProgram();
        if ($program === null) {
            return null;
        }

        return [
            ...self::presentProgram($program),
            'rewards' => LoyaltyReward::query()->where('active', true)->orderBy('cost')->orderBy('sort')->get()
                ->map(fn (LoyaltyReward $r) => self::presentReward($r))->values(),
        ];
    }

    /** @return array<string, mixed> */
    public static function presentProgram(LoyaltyProgram $p): array
    {
        return [
            'active' => $p->active,
            'name' => $p->name,
            'unit' => $p->unit(),
            'earn_mode' => $p->earn_mode,
            'earn_per_amount' => $p->earn_per_amount,
            'earn_min_order' => $p->earn_min_order,
            'category_ids' => $p->category_ids ?? [],
            'expiry_months' => $p->expiry_months,
        ];
    }

    /** @return array<string, mixed> */
    public static function presentReward(LoyaltyReward $r): array
    {
        return [
            'id' => $r->id,
            'name' => $r->name,
            'cost' => $r->cost,
            'type' => $r->type,
            'product_id' => $r->product_id,
            'value' => $r->value,
            'active' => $r->active,
            'sort' => $r->sort,
        ];
    }
}
