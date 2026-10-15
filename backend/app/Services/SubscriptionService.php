<?php

namespace App\Services;

use App\Mail\PaymentReceiptMail;
use App\Models\Device;
use App\Models\Outlet;
use App\Models\Plan;
use App\Models\Tenant;
use App\Models\User;
use App\Support\Audit;
use App\Support\OwnerMailer;
use App\Support\PlanCatalog;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Paket & langganan usaha. Belum ada payment gateway: daftar/upgrade ke paket berbayar dicatat sebagai
 * menunggu pembayaran, lalu admin mengaktifkan setelah uang diterima (`pos:activate-plan`).
 */
class SubscriptionService
{
    /** Paket yang ditawarkan, urut harga. */
    public static function publicPlans()
    {
        return Plan::query()->where('public', true)->orderBy('sort')->get();
    }

    /** Status awal usaha baru: gratis = coba 7 hari; berbayar = boleh dipakai 7 hari sambil menunggu bayar. */
    public function start(Tenant $tenant, Plan $plan, string $period): void
    {
        $free = $plan->code === PlanCatalog::FREE;
        // Diajak lewat kode referral: masa coba / batas bayar 14 hari.
        $days = $tenant->referred_by !== null ? ReferralService::REFERRED_TRIAL_DAYS : PlanCatalog::TRIAL_DAYS;
        $tenant->plan_id = $plan->id;
        $tenant->plan_status = $free ? 'trial' : 'awaiting_payment';
        $tenant->plan_period = $free ? null : $period;
        $tenant->plan_ends_at = now()->addDays($days);
        if (! $free) {
            $tenant->requested_plan_id = $plan->id;
            $tenant->requested_period = $period;
            $tenant->requested_at = now();
        }
        $tenant->save();
    }

    /** Owner memilih paket di halaman Upgrade: dicatat, menunggu pembayaran. */
    public function request(Tenant $tenant, Plan $plan, string $period): void
    {
        if (! $plan->public || $plan->code === PlanCatalog::FREE) {
            throw ValidationException::withMessages(['plan' => 'Pilih paket berbayar.']);
        }
        $before = ['plan' => $tenant->requestedPlan?->code, 'period' => $tenant->requested_period];
        $tenant->requested_plan_id = $plan->id;
        $tenant->requested_period = $period;
        $tenant->requested_at = now();
        $tenant->save();
        Audit::record('plan.requested', $tenant, before: $before, after: ['plan' => $plan->code, 'period' => $period]);
    }

    /**
     * Admin: pembayaran diterima → paket aktif sampai akhir periode (diperpanjang bila masih berjalan).
     * Mencatat pembayaran beserta diskon referral; mengembalikan rincian tagihan.
     *
     * @return array{base: int, percent: int, reason: ?string, amount: int}
     */
    public function activate(Tenant $tenant, Plan $plan, string $period, ?array $quote = null): array
    {
        return DB::transaction(fn () => $this->doActivate($tenant, $plan, $period, $quote));
    }

    /** @return array{base: int, percent: int, reason: ?string, amount: int} */
    private function doActivate(Tenant $tenant, Plan $plan, string $period, ?array $quote): array
    {
        $quote = app(ReferralService::class)->recordPayment($tenant, $plan, $period, $quote);
        $from = $tenant->plan_status === 'active' && $tenant->plan_id === $plan->id && $tenant->plan_ends_at?->isFuture()
            ? $tenant->plan_ends_at : now();
        $tenant->plan_id = $plan->id;
        $tenant->plan_status = 'active';
        $tenant->plan_period = $period;
        $tenant->plan_ends_at = $from->copy()->addMonths(PlanCatalog::months($period));
        $tenant->requested_plan_id = null;
        $tenant->requested_period = null;
        $tenant->requested_at = null;
        $tenant->save();

        if ($quote['base'] > 0) {
            $payment = DB::table('subscription_payments')->where('tenant_id', $tenant->id)->orderByDesc('created_at')->first();
            $endsAt = $tenant->plan_ends_at;
            OwnerMailer::send($tenant->id, fn ($owner, $t) => new PaymentReceiptMail(
                ownerName: $owner->name, businessName: $t->name, planName: $plan->name, period: $period,
                baseAmount: $quote['base'], discountPercent: $quote['percent'], discountReason: $quote['reason'],
                amount: $quote['amount'], activeUntil: $endsAt,
                receiptNo: 'STK-'.strtoupper(substr(str_replace('-', '', (string) $payment?->id), -10)), paidAt: now(),
            ));
        }

        return $quote;
    }

    /**
     * Tolak penambahan outlet / tablet / pegawai di atas batas paket. Dipanggil di dalam transaksi
     * yang sudah mengunci baris tenant.
     */
    public function assertLimit(string $what, int $current): void
    {
        $plan = Tenant::query()->with('plan')->findOrFail(app(TenantContext::class)->id())->plan;
        [$max, $field, $noun] = match ($what) {
            'outlets' => [$plan->max_outlets, 'name', 'outlet'],
            'devices' => [$plan->max_devices, 'device', 'tablet'],
            'staff' => [$plan->max_staff, 'name', 'pegawai (termasuk owner)'],
        };
        if ($max !== null && $current >= $max) {
            throw ValidationException::withMessages([
                $field => "Paket {$plan->name} maksimal {$max} {$noun}. Upgrade paket untuk menambah.",
            ]);
        }
    }

    /** @return array<string, mixed> */
    public function present(Tenant $tenant): array
    {
        $tenant->loadMissing('plan', 'requestedPlan');
        $usage = app(TenantContext::class)->run($tenant->id, fn () => [
            'outlets' => Outlet::query()->where('active', true)->count(),
            'devices' => Device::query()->whereNull('revoked_at')->count(),
            'staff' => User::query()->where('active', true)->count(),
        ]);

        return [
            'plan' => self::presentPlan($tenant->plan),
            'status' => $tenant->planExpired() ? 'expired' : $tenant->plan_status,
            'period' => $tenant->plan_period,
            'ends_at' => $tenant->plan_ends_at?->toIso8601String(),
            'days_left' => $tenant->plan_ends_at === null ? null
                : max(0, (int) ceil(now()->diffInSeconds($tenant->plan_ends_at, false) / 86400)),
            'requested' => $tenant->requestedPlan === null ? null : [
                'plan' => self::presentPlan($tenant->requestedPlan),
                'period' => $tenant->requested_period,
                'at' => $tenant->requested_at?->toIso8601String(),
            ],
            'usage' => $usage,
            // Diskon yang berlaku di pembayaran berikutnya (referral), dan kode untuk dibagikan.
            'discount' => array_intersect_key(app(ReferralService::class)->nextDiscount($tenant), ['percent' => 0, 'reason' => 0]),
            'referral' => app(ReferralService::class)->present($tenant),
            'plans' => self::publicPlans()->map(fn (Plan $p) => self::presentPlan($p))->values(),
        ];
    }

    /** @return array<string, mixed> */
    public static function presentPlan(Plan $plan): array
    {
        $features = DB::table('plan_features')->where('plan_id', $plan->id)->pluck('feature_key')->all();

        return [
            'code' => $plan->code, 'name' => $plan->name, 'tagline' => $plan->tagline,
            'price_month' => $plan->price_month, 'price_year' => $plan->price_year,
            // Harga tiap periode bayar (sudah termasuk diskon periode) + diskonnya.
            'prices' => collect(PlanCatalog::PERIODS)->map(fn ($p, $period) => PlanCatalog::price($plan->price_month, $period)),
            'period_discounts' => collect(PlanCatalog::PERIODS)->map(fn ($p) => $p[1]),
            'max_outlets' => $plan->max_outlets, 'max_devices' => $plan->max_devices, 'max_staff' => $plan->max_staff,
            'trial_days' => $plan->code === PlanCatalog::FREE ? PlanCatalog::TRIAL_DAYS : null,
            'recommended' => $plan->code === PlanCatalog::RECOMMENDED,
            'features' => $features,
        ];
    }
}
