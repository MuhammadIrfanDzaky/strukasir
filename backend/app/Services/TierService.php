<?php

namespace App\Services;

use App\Enums\Feature;
use App\Models\Customer;
use App\Models\MemberTier;
use App\Models\Order;
use App\Models\TenantSetting;
use App\Support\Tenancy\FeatureGate;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Tingkat member: dihitung saat dibaca dari order lunas dalam jendela N bulan terakhir
 * (total belanja atau jumlah kunjungan), sehingga naik/turun otomatis tanpa cron. Owner bisa
 * mengunci tingkat manual per pelanggan (`customers.tier_id`); tingkat nonaktif diabaikan.
 */
class TierService
{
    public const COLORS = ['bronze', 'silver', 'gold', 'platinum', 'indigo'];

    /** Fitur aktif & ada tingkat yang berlaku. */
    public function enabled(): bool
    {
        // FeatureGate diambil saat dipakai (scoped per request).
        return app(FeatureGate::class)->enabled(Feature::MemberTiers) && $this->tiers()->isNotEmpty();
    }

    /** @return Collection<int, MemberTier> tingkat aktif, ambang terendah dulu (dibaca sekali per request) */
    public function tiers(): Collection
    {
        $attributes = request()->attributes;
        if (! $attributes->has('member_tiers')) {
            $attributes->set('member_tiers', MemberTier::query()->where('active', true)->orderBy('threshold')->get());
        }

        return $attributes->get('member_tiers');
    }

    /** @return array{basis: string, window_months: ?int} */
    public function settings(): array
    {
        $s = TenantSetting::query()->first(['tier_basis', 'tier_window_months']);

        return ['basis' => $s?->tier_basis ?? 'spend', 'window_months' => $s?->tier_window_months];
    }

    /**
     * Ukuran kelayakan per pelanggan (Rp belanja atau jumlah order lunas) dalam jendela waktu.
     *
     * @return Builder<Order>
     */
    public function metricQuery(): Builder
    {
        ['basis' => $basis, 'window_months' => $window] = $this->settings();

        return Order::query()
            ->where('status', 'paid')
            ->whereNotNull('customer_id')
            ->when($window, fn ($q) => $q->where('paid_at', '>=', Carbon::now()->subMonths($window)))
            ->groupBy('customer_id')
            ->selectRaw('customer_id, '.($basis === 'visits' ? 'count(*)' : 'sum(grand_total)').' as tier_metric');
    }

    /**
     * Ekspresi SQL id tingkat efektif (kunci manual aktif, atau ambang tertinggi yang tercapai),
     * dipakai untuk filter daftar. Butuh kolom `tm.tier_metric` dari metricQuery().
     */
    public static function effectiveTierSql(): string
    {
        return 'coalesce((select mt.id from member_tiers mt where mt.id = customers.tier_id and mt.active), '
            .'(select mt.id from member_tiers mt where mt.active and mt.tenant_id = customers.tenant_id '
            .'and mt.threshold <= coalesce(tm.tier_metric, 0) order by mt.threshold desc limit 1))';
    }

    /**
     * Tingkat untuk satu pelanggan + kemajuan menuju tingkat berikutnya.
     *
     * @return array{tier: ?MemberTier, manual: bool, metric: int, next: ?MemberTier}
     */
    public function evaluate(Customer $customer, ?int $metric = null): array
    {
        $tiers = $this->tiers();
        $metric ??= (int) DB::query()->fromSub($this->metricQuery()->where('customer_id', $customer->id), 'm')->value('tier_metric');
        $manual = $customer->tier_id === null ? null : $tiers->firstWhere('id', $customer->tier_id);
        $earned = $tiers->filter(fn (MemberTier $t) => $t->threshold <= $metric)->last();
        $tier = $manual ?? $earned;
        $next = $tiers->first(fn (MemberTier $t) => $t->threshold > $metric && ($tier === null || $t->threshold > $tier->threshold));

        return ['tier' => $tier, 'manual' => $manual !== null, 'metric' => $metric, 'next' => $next];
    }

    /** @return array<string, mixed>|null */
    public static function present(?MemberTier $t, bool $manual = false): ?array
    {
        return $t === null ? null : [
            'id' => $t->id,
            'name' => $t->name,
            'threshold' => $t->threshold,
            'discount_bp' => $t->discount_bp,
            'earn_multiplier' => $t->earn_multiplier,
            'color' => $t->color,
            'manual' => $manual,
        ];
    }
}
