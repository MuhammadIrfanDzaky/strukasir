<?php

namespace App\Services;

use App\Enums\Feature;
use App\Models\Order;
use App\Models\Product;
use App\Models\Promotion;
use App\Models\Tenant;
use App\Models\Voucher;
use App\Support\Tenancy\FeatureGate;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Validation\ValidationException;

/**
 * Promo otomatis & voucher. Rumus potongan di sini dicerminkan app (lib/features/promotions) dan diuji
 * dengan kasus yang sama di kedua sisi:
 * - percent: ⌊harga baris × bp / 10000⌋ (sama dengan diskon % di PricingService)
 * - amount: min(nilai × qty, harga baris)
 * - price (harga spesial): max(0, harga dasar − nilai) × qty, maks. harga baris (tambahan tetap dibayar)
 * - min_qty (beli banyak): qty ≥ X → ⌊harga baris × bp / 10000⌋
 * - bogo (beli X gratis Y): ⌊qty / (X+Y)⌋ × Y porsi gratis × harga dasar produk, maks. harga baris
 * - bundle (paket): lihat bundles()
 *
 * Jadwal promo dinilai pada jam order dibuat (open bill yang dibuat saat happy hour tetap dapat promo
 * walau dibayar setelahnya), dalam zona waktu kedai.
 */
class PromotionService
{
    public function enabled(): bool
    {
        return app(FeatureGate::class)->enabled(Feature::Promotions);
    }

    public function now(): Carbon
    {
        return Carbon::now($this->timezone());
    }

    /** Jam penilaian promo: saat order dibuat (order lama) atau sekarang (order baru). */
    public function orderTime(?Order $existing): Carbon
    {
        return $existing?->created_at ? $existing->created_at->copy()->setTimezone($this->timezone()) : $this->now();
    }

    public function timezone(): string
    {
        return Tenant::query()->whereKey(app(TenantContext::class)->id())->value('timezone') ?: 'Asia/Jakarta';
    }

    /** @return Collection<int, Promotion> promo yang berlaku saat [$at] (dibaca sekali per request) */
    public function activeAt(Carbon $at): Collection
    {
        if (! $this->enabled()) {
            return collect();
        }
        $attributes = request()->attributes;
        if (! $attributes->has('promotions')) {
            $attributes->set('promotions', Promotion::query()->where('active', true)->orderBy('name')->get());
        }

        return $attributes->get('promotions')->filter(fn (Promotion $p) => self::runsAt($p, $at))->values();
    }

    public static function runsAt(Promotion $p, Carbon $at): bool
    {
        $date = $at->toDateString();
        if (($p->starts_on && $date < $p->starts_on->toDateString()) || ($p->ends_on && $date > $p->ends_on->toDateString())) {
            return false;
        }
        if ($p->days && ! in_array($at->dayOfWeekIso, $p->days, true)) {
            return false;
        }
        if (empty($p->times)) {
            return true;
        }
        $t = $at->format('H:i');
        foreach ($p->times as $w) {
            // Melewati tengah malam (mis. 22:00–02:00). Jam selesai tidak termasuk.
            $in = $w['start'] <= $w['end'] ? ($t >= $w['start'] && $t < $w['end']) : ($t >= $w['start'] || $t < $w['end']);
            if ($in) {
                return true;
            }
        }

        return false;
    }

    public static function covers(Promotion $p, Product $product): bool
    {
        return match ($p->scope) {
            'categories' => in_array($product->category_id, $p->target_ids ?? [], true),
            'products' => in_array($product->id, $p->target_ids ?? [], true),
            default => true,
        };
    }

    public static function discountFor(Promotion $p, Product $product, int $unitPrice, int $qty): int
    {
        if (! self::covers($p, $product)) {
            return 0;
        }
        $gross = $unitPrice * $qty;

        return match ($p->type) {
            'percent' => intdiv($gross * $p->value, 10000),
            'amount' => min($p->value * $qty, $gross),
            'price' => min(max(0, $product->price - $p->value) * $qty, $gross),
            'min_qty' => $qty >= $p->buy_qty ? intdiv($gross * $p->value, 10000) : 0,
            'bogo' => min(intdiv($qty, $p->buy_qty + $p->free_qty) * $p->free_qty * $product->price, $gross),
            default => 0, // bundle dihitung lintas baris (bundles())
        };
    }

    /**
     * Promo paket (bundle) lintas baris, sebelum promo per baris. Untuk tiap paket (urut nama):
     * jumlah set = min(⌊qty tersedia produk / qty di paket⌋); potongan = set × (harga normal − harga paket),
     * harga normal = Σ qty × harga dasar (tambahan tetap dibayar). Potongan dibagi per isi paket sebanding
     * harga normalnya (sisa pembulatan ke isi terakhir), lalu ke baris produk itu berurutan (maks. harga baris).
     * Baris yang terpakai paket tidak ikut paket lain / promo per baris / diskon member.
     *
     * @param  Collection<int, Promotion>  $promos
     * @param  array<int, array{product_id: string, price: int, qty: int, gross: int}>  $lines  baris yang boleh dapat promo
     * @return array<int, array{0: Promotion, 1: int}> indeks baris → [promo, potongan]
     */
    public static function bundles(Collection $promos, array $lines): array
    {
        $used = [];
        foreach ($promos as $p) {
            if ($p->type !== 'bundle' || empty($p->bundle_items)) {
                continue;
            }
            $parts = array_values($p->bundle_items);
            $free = fn (string $productId) => array_filter($lines, fn ($l, $i) => $l['product_id'] === $productId && ! isset($used[$i]), ARRAY_FILTER_USE_BOTH);
            $sets = PHP_INT_MAX;
            $normal = 0;
            foreach ($parts as $part) {
                $matches = $free($part['product_id']);
                $sets = min($sets, intdiv(array_sum(array_column($matches, 'qty')), $part['qty']));
                $normal += $part['qty'] * ($matches === [] ? 0 : reset($matches)['price']);
            }
            if ($sets < 1 || $normal <= $p->value) {
                continue;
            }
            $discount = $sets * ($normal - $p->value);
            $left = $discount;
            foreach ($parts as $j => $part) {
                $matches = $free($part['product_id']);
                $price = reset($matches)['price'];
                $share = $j === count($parts) - 1 ? $left : intdiv($discount * $part['qty'] * $price, $normal);
                $left -= $share;
                $units = $sets * $part['qty'];
                foreach ($matches as $i => $l) {
                    if ($units <= 0) {
                        break;
                    }
                    $units -= $l['qty'];
                    $amount = min($share, $l['gross']);
                    $share -= $amount;
                    $used[$i] = [$p, $amount];
                }
            }
        }

        return $used;
    }

    /**
     * Promo terbaik untuk satu baris.
     *
     * @param  Collection<int, Promotion>  $promos
     * @return array{0: ?Promotion, 1: int}
     */
    public static function best(Collection $promos, Product $product, int $unitPrice, int $qty): array
    {
        $best = [null, 0];
        foreach ($promos as $p) {
            $d = self::discountFor($p, $product, $unitPrice, $qty);
            if ($d > $best[1]) {
                $best = [$p, $d];
            }
        }

        return $best;
    }

    /**
     * Voucher yang berlaku untuk kode ini (huruf besar/kecil sama). Kuota = order lunas yang memakainya.
     *
     * @throws ValidationException
     */
    public function voucher(string $code, ?string $exceptOrderId = null, bool $lock = false): Voucher
    {
        $fail = fn (string $m) => throw ValidationException::withMessages(['voucher_code' => $m]);
        $this->enabled() || $fail('Fitur promo & voucher tidak aktif.');
        $voucher = Voucher::query()->where('code', mb_strtoupper(trim($code)))->when($lock, fn ($q) => $q->lockForUpdate())->first();
        if ($voucher === null || ! $voucher->active) {
            $fail('Kode voucher tidak ditemukan.');
        }
        $today = $this->now()->toDateString();
        if ($voucher->starts_on && $today < $voucher->starts_on->toDateString()) {
            $fail('Voucher belum berlaku (mulai '.$voucher->starts_on->format('d/m/Y').').');
        }
        if ($voucher->ends_on && $today > $voucher->ends_on->toDateString()) {
            $fail('Voucher sudah kedaluwarsa.');
        }
        if ($voucher->usage_limit !== null && $this->usage($voucher, $exceptOrderId) >= $voucher->usage_limit) {
            $fail('Kuota voucher sudah habis.');
        }

        return $voucher;
    }

    public function usage(Voucher $voucher, ?string $exceptOrderId = null): int
    {
        return Order::query()->where('voucher_id', $voucher->id)->where('status', 'paid')
            ->when($exceptOrderId, fn ($q) => $q->whereKeyNot($exceptOrderId))->count();
    }

    /** Potongan voucher dari subtotal (setelah diskon baris). */
    public static function voucherDiscount(Voucher $v, int $subtotal): int
    {
        if ($subtotal < $v->min_spend) {
            throw ValidationException::withMessages([
                'voucher_code' => 'Minimal belanja Rp'.number_format($v->min_spend, 0, ',', '.').' untuk voucher ini.',
            ]);
        }
        $d = $v->type === 'percent' ? intdiv($subtotal * $v->value, 10000) : $v->value;
        if ($v->max_discount !== null) {
            $d = min($d, $v->max_discount);
        }

        return min($d, $subtotal);
    }

    /** @return array<string, mixed> */
    public static function presentPromotion(Promotion $p): array
    {
        return [
            'id' => $p->id,
            'name' => $p->name,
            'type' => $p->type,
            'value' => $p->value,
            'buy_qty' => $p->buy_qty,
            'free_qty' => $p->free_qty,
            'scope' => $p->scope,
            'target_ids' => $p->target_ids ?? [],
            'bundle_items' => $p->bundle_items,
            'days' => $p->days,
            'times' => empty($p->times) ? null : array_values($p->times),
            // Rentang pertama untuk aplikasi versi lama (sebelum ada beberapa rentang jam).
            'start_time' => $p->times[0]['start'] ?? null,
            'end_time' => $p->times[0]['end'] ?? null,
            'starts_on' => $p->starts_on?->toDateString(),
            'ends_on' => $p->ends_on?->toDateString(),
            'active' => $p->active,
        ];
    }

    /** @return array<string, mixed> */
    public static function presentVoucher(Voucher $v, ?int $used = null): array
    {
        return [
            'id' => $v->id,
            'code' => $v->code,
            'type' => $v->type,
            'value' => $v->value,
            'max_discount' => $v->max_discount,
            'min_spend' => $v->min_spend,
            'starts_on' => $v->starts_on?->toDateString(),
            'ends_on' => $v->ends_on?->toDateString(),
            'usage_limit' => $v->usage_limit,
            'used' => $used,
            'active' => $v->active,
        ];
    }
}
