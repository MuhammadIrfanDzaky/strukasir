<?php

namespace App\Services;

use App\Enums\Feature;
use App\Enums\Permission;
use App\Models\Customer;
use App\Models\Device;
use App\Models\LoyaltyReward;
use App\Models\MemberTier;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\OrderItemModifier;
use App\Models\Payment;
use App\Models\Product;
use App\Models\Shift;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use App\Models\Voucher;
use App\Support\Approval;
use App\Support\Audit;
use App\Support\Pricing\PricingResult;
use App\Support\Pricing\PricingService;
use App\Support\Pricing\PricingSettings;
use App\Support\Tenancy\FeatureGate;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

/**
 * Siklus order: simpan (terbuka) → bayar. Server = sumber kebenaran harga; klien hanya mengirim
 * produk, qty, modifier, diskon, dan total yang ia harapkan (untuk mendeteksi menu basi).
 */
class OrderService
{
    public function __construct(
        private readonly PricingService $pricing,
        private readonly FeatureGate $features,
        private readonly LoyaltyService $loyalty,
        private readonly TierService $tiers,
        private readonly CreditService $credit,
        private readonly PromotionService $promotions,
    ) {}

    /**
     * Buat atau ganti isi order terbuka. Idempotent: PUT ulang dengan isi sama menghasilkan order sama.
     *
     * @param  array<string, mixed>  $data  hasil UpsertOrderRequest::validated()
     */
    public function upsert(string $orderId, array $data, User $cashier, Device $device, Tenant $tenant): Order
    {
        $existing = Order::query()->with('items')->find($orderId);
        if ($existing && $existing->status !== 'open') {
            throw new ConflictHttpException('Order ini sudah '.($existing->status === 'paid' ? 'dibayar' : 'dibatalkan').'.');
        }

        $products = $this->loadProducts($data['items']);
        $existingItemIds = $existing?->items->pluck('id')->all() ?? [];
        $lines = $this->buildLines($data['items'], $products, $existingItemIds);

        $this->guardDiscountFeature($data);
        $customer = $this->resolveCustomer($data['customer_id'] ?? null, $existing);
        [$lines, $orderDiscount, $reward] = $this->applyReward($data, $customer, $lines, $existing);
        [$lines, $tier] = $this->applyLineBenefits($data, $customer, $lines);
        [$orderDiscount, $voucher] = $this->applyVoucher($data, $lines, $orderDiscount, $reward, $existing);
        $result = $this->price($lines, $orderDiscount);
        $this->guardExpectedTotal($result, (int) $data['expected_total']);
        $rewardDiscount = $reward === null ? 0
            : ($reward['line_index'] !== null ? $result->lineDiscounts[$reward['line_index']] : $result->orderDiscount);
        $tierDiscount = array_sum(array_map(fn ($i) => ($lines[$i]['tier'] ?? false) ? $result->lineDiscounts[$i] : 0, array_keys($lines)));
        $promoDiscount = array_sum(array_map(fn ($i) => isset($lines[$i]['promo']) ? $result->lineDiscounts[$i] : 0, array_keys($lines)));
        $voucherDiscount = $voucher === null ? 0 : $result->orderDiscount;

        // Persetujuan diverifikasi SEBELUM transaksi: percobaan PIN gagal harus tetap tercatat.
        // Potongan hadiah sudah "dibayar" dengan stempel/poin, jadi tidak ikut batas diskon kasir.
        $approver = $this->authorizeDiscount($result, $lines, $cashier, $data['approval'] ?? null, $rewardDiscount + $tierDiscount + $promoDiscount + $voucherDiscount);

        $order = DB::transaction(function () use ($orderId, $data, $cashier, $device, $tenant, $lines, $result, $customer, $reward, $rewardDiscount, $tier, $tierDiscount, $promoDiscount, $voucher, $voucherDiscount) {
            $order = Order::query()->lockForUpdate()->find($orderId);

            if ($order === null) {
                $businessDate = $this->businessDate($tenant);
                $order = new Order;
                $order->id = $orderId;
                $order->forceFill([
                    'device_id' => $device->id,
                    'cashier_id' => $cashier->id,
                    'business_date' => $businessDate,
                    'client_created_at' => $data['client_created_at'] ?? null,
                    'number' => $this->nextNumber($businessDate, $device),
                ]);
            } elseif ($order->status !== 'open') {
                throw new ConflictHttpException('Order ini sudah tidak terbuka.');
            }

            $order->forceFill([
                // Member tanpa label → nama member (tampil di struk, open bill & riwayat).
                'customer_label' => ($data['customer_label'] ?? null) ?: $customer?->name,
                'customer_id' => $customer?->id,
                // Salinan hadiah: nama & harga stempel saat ditukar, baris yang digratiskan, besar potongan.
                'reward_id' => $reward['reward']->id ?? null,
                'reward_name' => $reward['reward']->name ?? null,
                'reward_cost' => $reward['reward']->cost ?? null,
                'reward_item_id' => $reward === null || $reward['line_index'] === null ? null : $lines[$reward['line_index']]['id'],
                'reward_discount' => $rewardDiscount,
                // Salinan tingkat member saat order disimpan (diskon & pengali stempel saat bayar).
                'tier_id' => $tier?->id,
                'tier_name' => $tier?->name,
                'tier_discount_bp' => $tier->discount_bp ?? 0,
                'tier_multiplier' => $tier->earn_multiplier ?? 1,
                'tier_discount' => $tierDiscount,
                'promo_discount' => $promoDiscount,
                'voucher_id' => $voucher?->id,
                'voucher_code' => $voucher?->code,
                'voucher_discount' => $voucherDiscount,
                'order_discount_type' => $data['order_discount']['type'] ?? null,
                'order_discount_value' => $data['order_discount']['value'] ?? 0,
                'subtotal' => $result->subtotal,
                'discount_total' => $result->discountTotal(),
                'service_total' => $result->serviceTotal,
                'tax_total' => $result->taxTotal,
                'service_bp' => $result->serviceBp,
                'tax_bp' => $result->taxBp,
                'service_inclusive' => $result->serviceInclusive,
                'tax_inclusive' => $result->taxInclusive,
                'rounding' => $result->rounding,
                'grand_total' => $result->grandTotal,
            ])->save();

            $order->items()->delete(); // modifier item ikut terhapus (cascade); order masih terbuka
            foreach ($lines as $i => $line) {
                $this->saveLine($order, $line, $result, $i);
            }

            return $order->refresh(); // muat nilai default DB (status, currency, ...)
        });

        if ($approver !== null) {
            Audit::record('discount.approved', $order, after: [
                'approver_id' => $approver->id,
                'discount_total' => $result->discountTotal(),
                'number' => $order->number,
            ], user: $cashier);
        }

        return $order;
    }

    /**
     * Pelanggan untuk order ini. Pelanggan dari kedai lain tidak ditemukan (global scope + RLS).
     * Tautan yang sudah ada tetap boleh dikirim ulang walau fitur dimatikan / datanya dianonimkan,
     * supaya open bill lama tetap bisa disimpan; tautan baru wajib fitur aktif & pelanggan aktif.
     */
    private function resolveCustomer(?string $customerId, ?Order $existing): ?Customer
    {
        if ($customerId === null) {
            return null;
        }
        $customer = Customer::query()->find($customerId);
        if ($customer !== null && $existing?->customer_id === $customer->id) {
            return $customer;
        }
        if (! $this->features->enabled(Feature::Customers)) {
            throw ValidationException::withMessages(['customer_id' => 'Fitur pelanggan tidak aktif.']);
        }
        if ($customer === null || $customer->isAnonymized()) {
            throw ValidationException::withMessages(['customer_id' => 'Pelanggan tidak ditemukan.']);
        }

        return $customer;
    }

    /**
     * Bayar order terbuka. Idempotent per ID pembayaran: kirim ulang setelah sukses → order yang sama.
     *
     * @param  list<array{id: string, method: string, amount: int, tendered?: int|null, reference?: string|null}>  $payments
     */
    public function pay(string $orderId, array $payments, int $expectedTotal, User $cashier, Device $device, ?array $approval = null): Order
    {
        if (count($payments) > 1 && ! $this->features->enabled(Feature::SplitPayment)) {
            throw ValidationException::withMessages(['payments' => 'Split payment tidak aktif untuk kedai ini.']);
        }

        // Kasbon: dicek sebelum transaksi (persetujuan PIN owner yang salah tetap tercatat).
        $creditAmount = array_sum(array_map(fn ($p) => $p['method'] === 'credit' ? (int) $p['amount'] : 0, $payments));
        $pending = $creditAmount > 0 ? Order::query()->find($orderId) : null;
        if ($pending !== null && $pending->status === 'open') {
            $approver = $this->credit->authorizeCharge($pending, $creditAmount, $cashier, $approval);
            if ($approver !== null) {
                Audit::record('credit.over_limit_approved', $pending, after: ['approver_id' => $approver->id, 'amount' => $creditAmount], user: $cashier, device: $device);
            }
        }

        return DB::transaction(function () use ($orderId, $payments, $expectedTotal, $cashier, $device) {
            $order = Order::query()->lockForUpdate()->findOrFail($orderId);
            $requestedIds = collect($payments)->pluck('id')->sort()->values()->all();

            if ($order->status === 'paid') {
                $paidIds = $order->payments()->pluck('id')->sort()->values()->all();
                if ($paidIds === $requestedIds) {
                    return $order; // kiriman ulang dari tablet (mis. koneksi putus setelah sukses)
                }
                throw new ConflictHttpException('Order ini sudah dibayar.');
            }
            if ($order->status !== 'open') {
                throw new ConflictHttpException('Order ini sudah dibatalkan.');
            }

            if ($expectedTotal !== $order->grand_total) {
                throw ValidationException::withMessages([
                    'expected_total' => 'Total order berubah ('.$order->grand_total.'). Muat ulang order.',
                ]);
            }

            $this->validatePayments($payments, $order->grand_total);

            $shiftId = app(ShiftService::class)->requireOpen($device)->id; // uang hanya bergerak di shift terbuka
            $now = now();
            $change = 0;

            foreach ($payments as $p) {
                $tendered = $p['method'] === 'cash' ? ($p['tendered'] ?? $p['amount']) : null;
                $payment = new Payment;
                $payment->forceFill([
                    'id' => $p['id'],
                    'order_id' => $order->id,
                    'shift_id' => $shiftId,
                    'kind' => 'payment',
                    'method' => $p['method'],
                    'amount' => $p['amount'],
                    'tendered' => $tendered,
                    'change' => $tendered === null ? 0 : $tendered - $p['amount'],
                    'reference' => $p['reference'] ?? null,
                    'confirmed_by' => $cashier->id,
                    'confirmed_at' => $now,
                ])->save();
                $change += $payment->change;
            }

            $order->forceFill([
                'status' => 'paid',
                'shift_id' => $order->shift_id ?? $shiftId,
                'paid_total' => array_sum(array_column($payments, 'amount')),
                'change_total' => $change,
                'paid_at' => $now,
            ])->save();

            // Kuota voucher dicek ulang dengan kunci (dua order bersamaan tidak melewati kuota).
            if ($order->voucher_id !== null) {
                $this->promotions->voucher((string) $order->voucher_code, $order->id, lock: true);
            }

            // Tukar hadiah & catat stempel/poin member di transaksi yang sama: gagal = bayar dibatalkan.
            $this->loyalty->onPaid($order, $cashier);

            Audit::record('order.paid', $order, after: [
                'number' => $order->number,
                'grand_total' => $order->grand_total,
                'methods' => array_column($payments, 'method'),
            ], user: $cashier, device: $device);

            return $order;
        });
    }

    /**
     * Batalkan order. Terbuka → void saja. Lunas → void + refund (baris pembayaran baru kind=refund,
     * metode sama) di shift yang sedang terbuka, karena di situlah uang keluar dari laci/rekening.
     * Kasir butuh persetujuan PIN owner; alasan selalu wajib. Kiriman ulang aman.
     *
     * @param  array{user_id?: string, pin?: string}|null  $approval
     */
    public function void(string $orderId, string $reason, ?array $approval, User $user, Device $device): Order
    {
        $approver = Gate::forUser($user)->allows(Permission::OrderVoid->value)
            ? $user
            : Approval::verify($approval, Permission::OrderVoid); // di luar transaksi: PIN salah tetap tercatat

        return DB::transaction(function () use ($orderId, $reason, $user, $device, $approver) {
            $order = Order::query()->lockForUpdate()->findOrFail($orderId);
            if ($order->status === 'void') {
                return $order;
            }

            $refunded = 0;
            if ($order->status === 'paid') {
                $shiftId = app(ShiftService::class)->requireOpen($device)->id;
                foreach ($order->payments()->where('kind', 'payment')->get() as $p) {
                    (new Payment)->forceFill([
                        'order_id' => $order->id,
                        'shift_id' => $shiftId,
                        'kind' => 'refund',
                        'method' => $p->method,
                        'amount' => $p->amount,
                        'reference' => 'refund:'.$p->id,
                        'confirmed_by' => $user->id,
                        'confirmed_at' => now(),
                    ])->save();
                    $refunded += $p->amount;
                }
            }

            if ($order->status === 'paid') {
                $this->loyalty->onVoid($order, $user);
            }

            $before = $order->status;
            $order->forceFill([
                'status' => 'void',
                'voided_at' => now(),
                'voided_by' => $approver->id,
                'void_reason' => $reason,
            ])->save();

            Audit::record('order.voided', $order, ['status' => $before], [
                'number' => $order->number,
                'reason' => $reason,
                'approver_id' => $approver->id,
                'refunded' => $refunded,
            ], user: $user, device: $device);

            return $order;
        });
    }

    // ───────────────────────────── validasi menu ─────────────────────────────

    /** @return Collection<string, Product> */
    private function loadProducts(array $items): Collection
    {
        return Product::query()
            ->with('modifierGroups.modifiers')
            ->whereIn('id', array_unique(array_column($items, 'product_id')))
            ->get()
            ->keyBy('id');
    }

    /**
     * Ubah item request menjadi baris tervalidasi + snapshot. Produk/modifier baru wajib aktif;
     * item yang sudah ada di order terbuka boleh tetap ada walau produknya kini habis.
     *
     * @return list<array<string, mixed>>
     */
    private function buildLines(array $items, Collection $products, array $existingItemIds): array
    {
        $modifiersOn = $this->features->enabled(Feature::Modifiers);
        $lines = [];

        foreach (array_values($items) as $i => $item) {
            $field = "items.{$i}";
            $product = $products->get($item['product_id'])
                ?? throw ValidationException::withMessages(["{$field}.product_id" => 'Produk tidak ditemukan.']);
            $isNew = ! in_array($item['id'], $existingItemIds, true);

            if ($isNew && (! $product->active || $product->sold_out)) {
                throw ValidationException::withMessages(["{$field}.product_id" => "{$product->name} sedang tidak tersedia."]);
            }

            $chosen = [];
            if (! $modifiersOn && $item['modifier_ids'] !== []) {
                throw ValidationException::withMessages(["{$field}.modifier_ids" => 'Fitur modifier tidak aktif.']);
            }

            if ($modifiersOn) {
                // ID diulang = jumlah opsi itu (mis. Extra shot x2).
                $counts = array_count_values(array_map('strval', $item['modifier_ids']));

                foreach ($product->modifierGroups as $group) {
                    $picked = $group->modifiers->whereIn('id', array_keys($counts));
                    if ($isNew && $picked->contains(fn ($m) => ! $m->active)) {
                        throw ValidationException::withMessages(["{$field}.modifier_ids" => "Pilihan {$group->name} tidak tersedia."]);
                    }
                    $total = 0;
                    foreach ($picked as $m) {
                        $qty = $counts[$m->id];
                        if ($qty > 1 && ! $group->allow_quantity) {
                            throw ValidationException::withMessages(["{$field}.modifier_ids" => "{$m->name} hanya bisa dipilih satu kali."]);
                        }
                        if ($qty > $group->max_quantity && $group->allow_quantity) {
                            throw ValidationException::withMessages([
                                "{$field}.modifier_ids" => "{$m->name} maksimal {$group->max_quantity}x.",
                            ]);
                        }
                        $total += $qty;
                    }
                    if ($total < $group->min_select || $total > $group->max_select) {
                        throw ValidationException::withMessages([
                            "{$field}.modifier_ids" => "{$product->name}: pilihan {$group->name} harus {$group->min_select}–{$group->max_select}.",
                        ]);
                    }
                    foreach ($picked as $m) {
                        $chosen[] = [
                            'modifier_id' => $m->id, 'group_name' => $group->name, 'name' => $m->name,
                            'price_delta' => $m->price_delta, 'qty' => $counts[$m->id],
                        ];
                    }
                }

                if (array_sum(array_column($chosen, 'qty')) !== count($item['modifier_ids'])) {
                    throw ValidationException::withMessages(["{$field}.modifier_ids" => 'Pilihan tidak sesuai dengan produk.']);
                }
            }

            $lines[] = [
                'id' => $item['id'],
                'product' => $product,
                'qty' => $item['qty'],
                'note' => $item['note'] ?? null,
                'modifiers' => $chosen,
                'modifiers_total' => array_sum(array_map(fn (array $m) => $m['price_delta'] * $m['qty'], $chosen)),
                'discount' => $item['discount'] ?? null,
            ];
        }

        return $lines;
    }

    // ───────────────────────────── harga & diskon ─────────────────────────────

    private function price(array $lines, ?array $orderDiscount): PricingResult
    {
        $settings = TenantSetting::query()->firstOrFail();

        try {
            return $this->pricing->calculate(
                array_map(fn (array $l) => [
                    'unit_price' => $l['product']->price + $l['modifiers_total'],
                    'qty' => $l['qty'],
                    'discount' => $l['discount'],
                ], $lines),
                $orderDiscount,
                PricingSettings::fromTenant($settings, $this->features->enabled(Feature::TaxService)),
            );
        } catch (InvalidArgumentException $e) {
            throw ValidationException::withMessages(['discount' => $e->getMessage()]);
        }
    }

    /**
     * Terapkan hadiah loyalitas sebagai diskon: gratis produk = potongan harga dasar 1 porsi di barisnya;
     * potongan Rp / % = diskon order (tidak bisa digabung dengan diskon order manual).
     *
     * @return array{0: list<array<string, mixed>>, 1: ?array{type: string, value: int}, 2: ?array{reward: LoyaltyReward, line_index: ?int}}
     */
    private function applyReward(array $data, ?Customer $customer, array $lines, ?Order $existing): array
    {
        $orderDiscount = $data['order_discount'] ?? null;
        $reward = $this->loyalty->resolveReward($data['reward'] ?? null, $customer, $lines, $existing);
        if ($reward === null) {
            return [$lines, $orderDiscount, null];
        }

        $r = $reward['reward'];
        if ($r->type === 'free_product') {
            $i = $reward['line_index'];
            $lines[$i]['discount'] = ['type' => 'amount', 'value' => $lines[$i]['product']->price];
            $lines[$i]['reward'] = true;

            return [$lines, $orderDiscount, $reward];
        }

        if (! empty($orderDiscount['value'])) {
            throw ValidationException::withMessages(['order_discount' => 'Hadiah potongan tidak bisa digabung dengan diskon order.']);
        }
        $orderDiscount = $r->type === 'percent'
            ? ['type' => 'percent', 'value' => $r->value]
            : ['type' => 'amount', 'value' => min($r->value, $this->price($lines, null)->subtotal)];

        return [$lines, $orderDiscount, $reward];
    }

    /**
     * Diskon tingkat member: persen tingkat di setiap baris yang belum punya diskon (manual / hadiah).
     * Tablet mengirim tingkat yang dipakainya; bila berbeda dari tingkat sekarang, minta pilih ulang member.
     *
     * @return array{0: list<array<string, mixed>>, 1: ?MemberTier}
     */
    private static function automatic(array $line): bool
    {
        return ($line['reward'] ?? false) || ($line['tier'] ?? false) || isset($line['promo']);
    }

    /**
     * Diskon otomatis per baris tanpa diskon lain (manual / hadiah): yang terbesar antara promo yang
     * sedang berlaku dan diskon tingkat member (seri → promo). Tablet mengirim tingkat yang dipakainya;
     * bila berbeda dari tingkat sekarang, minta pilih ulang member.
     *
     * @return array{0: list<array<string, mixed>>, 1: ?MemberTier}
     */
    private function applyLineBenefits(array $data, ?Customer $customer, array $lines): array
    {
        $tier = $customer !== null && ! $customer->isAnonymized() && $this->tiers->enabled()
            ? $this->tiers->evaluate($customer)['tier'] : null;
        $promos = $this->promotions->activeAt($this->promotions->now());

        if (array_key_exists('tier_id', $data) && ($data['tier_id'] ?? null) !== $tier?->id) {
            throw ValidationException::withMessages([
                'customer_id' => 'Tingkat member pelanggan ini berubah'.($tier ? " (sekarang {$tier->name})" : '').'. Pilih ulang membernya.',
            ]);
        }
        foreach ($lines as $i => $line) {
            if (! empty($line['discount']) || ($line['reward'] ?? false)) {
                continue;
            }
            $unit = $line['product']->price + $line['modifiers_total'];
            [$promo, $promoAmount] = PromotionService::best($promos, $line['product'], $unit, $line['qty']);
            $tierAmount = $tier && $tier->discount_bp > 0 ? intdiv($unit * $line['qty'] * $tier->discount_bp, 10000) : 0;
            if ($promo !== null && $promoAmount >= $tierAmount) {
                $lines[$i]['discount'] = ['type' => 'amount', 'value' => $promoAmount];
                $lines[$i]['promo'] = $promo->name;
            } elseif ($tierAmount > 0) {
                $lines[$i]['discount'] = ['type' => 'percent', 'value' => $tier->discount_bp];
                $lines[$i]['tier'] = true;
            }
        }

        return [$lines, $tier];
    }

    /**
     * Voucher kode → diskon order (Rp). Tidak bisa digabung dengan diskon order manual / hadiah potongan.
     *
     * @return array{0: ?array{type: string, value: int}, 1: ?Voucher}
     */
    private function applyVoucher(array $data, array $lines, ?array $orderDiscount, ?array $reward, ?Order $existing): array
    {
        $code = trim((string) ($data['voucher_code'] ?? ''));
        if ($code === '') {
            return [$orderDiscount, null];
        }
        if (! empty($orderDiscount['value'])) {
            throw ValidationException::withMessages(['voucher_code' => 'Voucher tidak bisa digabung dengan diskon order / hadiah potongan.']);
        }
        $voucher = $this->promotions->voucher($code, $existing?->id);
        $subtotal = $this->price($lines, null)->subtotal;

        return [['type' => 'amount', 'value' => PromotionService::voucherDiscount($voucher, $subtotal)], $voucher];
    }

    private function guardDiscountFeature(array $data): void
    {
        $hasDiscount = ! empty($data['order_discount']['value'])
            || collect($data['items'])->contains(fn ($i) => ! empty($i['discount']['value']));

        if ($hasDiscount && ! $this->features->enabled(Feature::Discounts)) {
            throw ValidationException::withMessages(['discount' => 'Fitur diskon tidak aktif untuk kedai ini.']);
        }
    }

    private function guardExpectedTotal(PricingResult $result, int $expected): void
    {
        if ($expected !== $result->grandTotal) {
            throw ValidationException::withMessages([
                'expected_total' => 'Harga di tablet berbeda dengan server (server: '.$result->grandTotal.'). Muat ulang menu.',
            ]);
        }
    }

    /**
     * Diskon sampai batas kedai boleh oleh kasir; di atasnya wajib persetujuan owner.
     * Persentase dihitung dari total diskon terhadap total kotor seluruh baris.
     */
    private function authorizeDiscount(PricingResult $result, array $lines, User $cashier, ?array $approval, int $rewardDiscount = 0): ?User
    {
        $discount = $result->discountTotal() - $rewardDiscount;
        if ($discount === 0 || Gate::forUser($cashier)->allows(Permission::DiscountOverLimit->value)) {
            return null;
        }

        $gross = array_sum(array_map(fn (array $l) => ($l['product']->price + $l['modifiers_total']) * $l['qty'], $lines));
        $rateBp = $gross > 0 ? intdiv($discount * 10000 + $gross - 1, $gross) : 10000; // dibulatkan ke atas
        $limitBp = TenantSetting::query()->value('cashier_discount_limit_bp') ?? 0;

        if ($rateBp <= $limitBp && Gate::forUser($cashier)->allows(Permission::DiscountWithinLimit->value)) {
            return null;
        }

        return Approval::verify($approval, Permission::DiscountOverLimit);
    }

    // ───────────────────────────── penyimpanan ─────────────────────────────

    private function saveLine(Order $order, array $line, PricingResult $result, int $i): void
    {
        $item = new OrderItem;
        $item->forceFill([
            'id' => $line['id'],
            'order_id' => $order->id,
            'product_id' => $line['product']->id,
            'name' => $line['product']->name,
            'unit_price' => $line['product']->price,
            // Salinan modal saat transaksi: laba kotor tidak berubah bila modal diubah belakangan.
            'unit_cost' => $line['product']->cost,
            'qty' => $line['qty'],
            'modifiers_total' => $line['modifiers_total'],
            // Baris hadiah: potongan tercatat di discount_total, bukan sebagai diskon manual.
            // Diskon otomatis (hadiah, tingkat, promo): tercatat di discount_total, bukan diskon manual.
            'discount_type' => self::automatic($line) ? null : ($line['discount']['type'] ?? null),
            'discount_value' => self::automatic($line) ? 0 : ($line['discount']['value'] ?? 0),
            'promo_name' => $line['promo'] ?? null,
            'discount_total' => $result->lineDiscounts[$i],
            'line_total' => $result->lines[$i],
            'note' => $line['note'],
            'sort' => $i,
        ])->save();

        foreach ($line['modifiers'] as $m) {
            (new OrderItemModifier)->forceFill([...$m, 'order_item_id' => $item->id])->save();
        }
    }

    private function businessDate(Tenant $tenant): string
    {
        return now()->setTimezone($tenant->timezone)->toDateString();
    }

    /** Nomor order berurutan per kedai per hari bisnis, mis. "T1-0042". Dikunci agar tidak dobel. */
    private function nextNumber(string $businessDate, Device $device): string
    {
        $tenantId = $device->tenant_id;
        DB::table('order_counters')->insertOrIgnore([
            'tenant_id' => $tenantId, 'business_date' => $businessDate, 'last_number' => 0,
        ]);

        $next = DB::table('order_counters')
            ->where('tenant_id', $tenantId)->where('business_date', $businessDate)
            ->lockForUpdate()->value('last_number') + 1;

        DB::table('order_counters')
            ->where('tenant_id', $tenantId)->where('business_date', $businessDate)
            ->update(['last_number' => $next]);

        return sprintf('%s-%04d', $device->code, $next);
    }

    /** @param  list<array{id: string, method: string, amount: int, tendered?: int|null}>  $payments */
    private function validatePayments(array $payments, int $grandTotal): void
    {
        if ($grandTotal === 0) {
            if ($payments !== []) {
                throw ValidationException::withMessages(['payments' => 'Order bernilai nol tidak perlu pembayaran.']);
            }

            return;
        }
        if ($payments === []) {
            throw ValidationException::withMessages(['payments' => 'Pilih metode pembayaran.']);
        }

        if (count(array_filter($payments, fn ($p) => $p['method'] === 'cash')) > 1) {
            throw ValidationException::withMessages(['payments' => 'Pembayaran tunai cukup satu baris.']);
        }
        if (count(array_filter($payments, fn ($p) => $p['method'] === 'credit')) > 1) {
            throw ValidationException::withMessages(['payments' => 'Kasbon cukup satu baris.']);
        }

        foreach ($payments as $i => $p) {
            if ($p['method'] !== 'cash' && isset($p['tendered'])) {
                throw ValidationException::withMessages(["payments.{$i}.tendered" => 'Uang diterima hanya untuk tunai.']);
            }
            if ($p['method'] === 'cash' && isset($p['tendered']) && $p['tendered'] < $p['amount']) {
                throw ValidationException::withMessages(["payments.{$i}.tendered" => 'Uang diterima kurang dari nominal.']);
            }
        }

        $sum = array_sum(array_column($payments, 'amount'));
        if ($sum !== $grandTotal) {
            throw ValidationException::withMessages([
                'payments' => "Jumlah pembayaran ({$sum}) harus sama dengan total ({$grandTotal}).",
            ]);
        }
    }
}
