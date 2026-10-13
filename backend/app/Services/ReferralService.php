<?php

namespace App\Services;

use App\Models\Plan;
use App\Models\Tenant;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Referral antarusaha. Yang diajak: coba 14 hari + diskon 25% sekali di pembayaran paket pertama.
 * Pengajak: satu kupon 50% untuk setiap usaha ajakan yang membayar paket pertama kali; satu kupon
 * dipakai di satu pembayaran (kupon lain menunggu pembayaran berikutnya). Diskon tidak ditumpuk.
 */
class ReferralService
{
    public const REFERRED_TRIAL_DAYS = 14;

    public const REFERRED_PERCENT = 25;

    public const REWARD_PERCENT = 50;

    /** Kode 6 huruf/angka tanpa karakter mirip (0/O, 1/I/L). */
    public static function newCode(): string
    {
        $alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
        do {
            $code = '';
            for ($i = 0; $i < 6; $i++) {
                $code .= $alphabet[random_int(0, strlen($alphabet) - 1)];
            }
        } while (DB::table('tenants')->where('referral_code', $code)->exists());

        return $code;
    }

    public static function normalize(?string $code): ?string
    {
        $code = strtoupper(preg_replace('/\s+/', '', (string) $code));

        return $code === '' ? null : $code;
    }

    public function findReferrer(?string $code): ?Tenant
    {
        $code = self::normalize($code);

        return $code === null ? null : Tenant::query()->where('referral_code', $code)->first();
    }

    /** Sudah pernah membayar paket (bukan gratis)? */
    private function hasPaid(Tenant $tenant): bool
    {
        return DB::table('subscription_payments')->where('tenant_id', $tenant->id)->where('base_amount', '>', 0)->exists();
    }

    /**
     * Diskon untuk pembayaran berikutnya (tanpa memakainya).
     *
     * @return array{percent: int, reason: ?string, reward_id: ?string}
     */
    public function nextDiscount(Tenant $tenant): array
    {
        if ($tenant->referred_by !== null && ! $this->hasPaid($tenant)) {
            return ['percent' => self::REFERRED_PERCENT, 'reason' => 'referred', 'reward_id' => null];
        }
        $reward = DB::table('referral_rewards')->where('referrer_id', $tenant->id)->whereNull('used_at')
            ->orderBy('created_at')->first();

        return $reward === null
            ? ['percent' => 0, 'reason' => null, 'reward_id' => null]
            : ['percent' => (int) $reward->percent, 'reason' => 'referral_reward', 'reward_id' => $reward->id];
    }

    public static function price(Plan $plan, string $period): int
    {
        return $period === 'year' ? $plan->price_year : $plan->price_month;
    }

    /** @return array{base: int, percent: int, reason: ?string, amount: int} */
    public function quote(Tenant $tenant, Plan $plan, string $period): array
    {
        $base = self::price($plan, $period);
        $discount = $base > 0 ? $this->nextDiscount($tenant) : ['percent' => 0, 'reason' => null];

        return [
            'base' => $base, 'percent' => $discount['percent'], 'reason' => $discount['reason'],
            'amount' => (int) round($base * (100 - $discount['percent']) / 100, -2), // dibulatkan ke ratusan
        ];
    }

    /**
     * Catat pembayaran yang diaktifkan admin: pakai diskon yang berlaku, dan bila ini pembayaran pertama
     * usaha ajakan, beri pengajaknya satu kupon. Dipanggil di dalam transaksi aktivasi.
     *
     * @return array{base: int, percent: int, reason: ?string, amount: int}
     */
    public function recordPayment(Tenant $tenant, Plan $plan, string $period): array
    {
        Tenant::query()->whereKey($tenant->id)->lockForUpdate()->first();
        $firstPaid = ! $this->hasPaid($tenant);
        $discount = $this->nextDiscount($tenant);
        $quote = $this->quote($tenant, $plan, $period);

        $paymentId = (string) Str::uuid7();
        DB::table('subscription_payments')->insert([
            'id' => $paymentId, 'tenant_id' => $tenant->id, 'plan_id' => $plan->id, 'period' => $period,
            'base_amount' => $quote['base'], 'discount_percent' => $quote['percent'], 'discount_reason' => $quote['reason'],
            'amount' => $quote['amount'], 'created_at' => now(),
        ]);
        if ($quote['reason'] === 'referral_reward') {
            DB::table('referral_rewards')->where('id', $discount['reward_id'])->update(['used_at' => now(), 'used_payment_id' => $paymentId]);
        }

        if ($firstPaid && $quote['base'] > 0 && $tenant->referred_by !== null) {
            DB::table('referral_rewards')->insertOrIgnore([
                'id' => (string) Str::uuid7(), 'referrer_id' => $tenant->referred_by, 'referee_id' => $tenant->id,
                'percent' => self::REWARD_PERCENT, 'created_at' => now(),
            ]);
        }

        return $quote;
    }

    /** @return array<string, mixed> */
    public function present(Tenant $tenant): array
    {
        $invited = Tenant::query()->where('referred_by', $tenant->id)->count();
        $rewards = DB::table('referral_rewards')->where('referrer_id', $tenant->id);

        return [
            'code' => $tenant->referral_code,
            'invited' => $invited,
            'paid' => (clone $rewards)->count(),
            'rewards_available' => (clone $rewards)->whereNull('used_at')->count(),
            'referred_percent' => self::REFERRED_PERCENT,
            'reward_percent' => self::REWARD_PERCENT,
            'trial_days' => self::REFERRED_TRIAL_DAYS,
        ];
    }
}
