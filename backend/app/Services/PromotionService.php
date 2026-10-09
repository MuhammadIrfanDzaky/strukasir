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
 * - bogo (beli X gratis Y): ⌊qty / (X+Y)⌋ × Y porsi gratis × harga dasar produk, maks. harga baris
 */
class PromotionService
{
    public function enabled(): bool
    {
        return app(FeatureGate::class)->enabled(Feature::Promotions);
    }

    public function now(): Carbon
    {
        $tz = Tenant::query()->whereKey(app(TenantContext::class)->id())->value('timezone') ?: 'Asia/Jakarta';

        return Carbon::now($tz);
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
        if ($p->start_time === null || $p->end_time === null) {
            return true;
        }
        $t = $at->format('H:i:s');
        $start = substr($p->start_time, 0, 8);
        $end = substr($p->end_time, 0, 8);

        // Melewati tengah malam (mis. 22:00–02:00).
        return $start <= $end ? ($t >= $start && $t < $end) : ($t >= $start || $t < $end);
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
            default => min(intdiv($qty, $p->buy_qty + $p->free_qty) * $p->free_qty * $product->price, $gross),
        };
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
            'days' => $p->days,
            'start_time' => $p->start_time ? substr($p->start_time, 0, 5) : null,
            'end_time' => $p->end_time ? substr($p->end_time, 0, 5) : null,
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
