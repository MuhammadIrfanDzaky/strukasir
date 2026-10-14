<?php

namespace App\Services\Payments;

use App\Models\Plan;
use App\Models\Tenant;
use App\Services\ReferralService;
use App\Services\SubscriptionService;
use App\Support\Audit;
use App\Support\PlanCatalog;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use stdClass;
use Throwable;

/**
 * Bayar paket lewat QRIS (Midtrans): tagihan dibuat server dengan harga & diskon terkunci, lalu dianggap
 * lunas hanya bila status dari Midtrans (diambil server) = settlement dengan jumlah yang sama.
 * Notifikasi & polling app memakai jalur yang sama (`sync`) dan idempotent per tagihan.
 */
class SubscriptionCheckout
{
    public function __construct(private readonly Midtrans $midtrans) {}

    public function enabled(): bool
    {
        return $this->midtrans->enabled();
    }

    public function create(Tenant $tenant, Plan $plan, string $period): stdClass
    {
        if (! $plan->public || $plan->code === PlanCatalog::FREE) {
            throw ValidationException::withMessages(['plan' => 'Pilih paket berbayar.']);
        }
        // Tagihan QR yang masih berlaku untuk paket & periode sama dipakai ulang (tidak menumpuk QR).
        $open = DB::table('subscription_invoices')->where('tenant_id', $tenant->id)->where('status', 'pending')
            ->where('plan_id', $plan->id)->where('period', $period)->where('expires_at', '>', now()->addMinute())
            ->orderByDesc('created_at')->first();
        $quote = app(ReferralService::class)->quote($tenant, $plan, $period);
        if ($open !== null && (int) $open->amount === $quote['amount']) {
            return $open;
        }

        $id = (string) Str::uuid7();
        $orderId = 'STK-'.strtoupper(Str::random(6)).'-'.now()->format('ymdHis');
        $minutes = (int) config('services.midtrans.qris_expiry_minutes', 15);
        $charge = $this->midtrans->chargeQris($orderId, $quote['amount'], $minutes);

        DB::table('subscription_invoices')->insert([
            'id' => $id, 'tenant_id' => $tenant->id, 'plan_id' => $plan->id, 'period' => $period,
            'base_amount' => $quote['base'], 'discount_percent' => $quote['percent'], 'discount_reason' => $quote['reason'],
            'amount' => $quote['amount'], 'order_id' => $orderId, 'gateway_ref' => $charge['transaction_id'],
            'status' => 'pending', 'qr_string' => $charge['qr_string'], 'qr_url' => $charge['qr_url'],
            // expiry_time Midtrans dalam WIB tanpa zona waktu.
            'expires_at' => $charge['expires_at'] !== null
                ? Carbon::parse($charge['expires_at'], 'Asia/Jakarta')->utc() : now()->addMinutes($minutes),
            'created_at' => now(), 'updated_at' => now(),
        ]);
        Audit::record('plan.checkout', $tenant, after: ['plan' => $plan->code, 'period' => $period, 'amount' => $quote['amount'], 'order_id' => $orderId]);

        return DB::table('subscription_invoices')->where('id', $id)->first();
    }

    /** Cocokkan status tagihan dengan Midtrans; lunas → paket aktif (sekali saja). */
    public function sync(stdClass $invoice): stdClass
    {
        if ($invoice->status !== 'pending') {
            return $invoice;
        }
        $status = $this->midtrans->status($invoice->order_id);
        if ($status === null) {
            return $invoice;
        }

        return $this->apply($invoice->id, $status);
    }

    /** @param array<string, mixed> $status hasil GET status Midtrans */
    private function apply(string $invoiceId, array $status): stdClass
    {
        return DB::transaction(function () use ($invoiceId, $status) {
            $invoice = DB::table('subscription_invoices')->where('id', $invoiceId)->lockForUpdate()->first();
            if ($invoice->status !== 'pending') {
                return $invoice; // notifikasi/polling ganda
            }
            $next = Midtrans::mapStatus($status);
            // Jumlah harus sama persis dengan tagihan (gross_amount Midtrans berupa "24900.00").
            if ($next === 'paid' && (int) round((float) ($status['gross_amount'] ?? -1)) !== (int) $invoice->amount) {
                report(new \RuntimeException("Jumlah Midtrans tidak cocok untuk {$invoice->order_id}"));

                return $invoice;
            }
            if ($next === 'pending') {
                return $invoice;
            }

            $update = ['status' => $next, 'updated_at' => now()];
            if ($next === 'paid') {
                $tenant = Tenant::query()->findOrFail($invoice->tenant_id);
                $plan = Plan::query()->findOrFail($invoice->plan_id);
                app(SubscriptionService::class)->activate($tenant, $plan, $invoice->period, [
                    'base' => (int) $invoice->base_amount, 'percent' => (int) $invoice->discount_percent,
                    'reason' => $invoice->discount_reason, 'amount' => (int) $invoice->amount,
                ]);
                $update['paid_at'] = now();
                $update['payment_id'] = DB::table('subscription_payments')->where('tenant_id', $tenant->id)
                    ->orderByDesc('created_at')->value('id');
                // Notifikasi datang tanpa konteks usaha: catat audit di usaha pemilik tagihan.
                app(TenantContext::class)->run($tenant->id, fn () => Audit::record('plan.paid', $tenant, after: [
                    'plan' => $plan->code, 'period' => $invoice->period, 'amount' => (int) $invoice->amount, 'order_id' => $invoice->order_id,
                ]));
            }
            DB::table('subscription_invoices')->where('id', $invoiceId)->update($update);

            return DB::table('subscription_invoices')->where('id', $invoiceId)->first();
        });
    }

    /**
     * Notifikasi HTTP Midtrans. Tanda tangan dicek, lalu status diambil ulang dari Midtrans (bukan dari isi
     * notifikasi). Mengembalikan false bila tanda tangan salah.
     *
     * @param array<string, mixed> $payload
     */
    public function handleNotification(array $payload): bool
    {
        if (! $this->midtrans->validSignature($payload)) {
            return false;
        }
        $invoice = DB::table('subscription_invoices')->where('order_id', (string) ($payload['order_id'] ?? ''))->first();
        if ($invoice !== null) {
            try {
                $this->sync($invoice);
            } catch (Throwable $e) {
                report($e);
                throw $e; // 5xx → Midtrans mengirim ulang notifikasi
            }
        }

        return true;
    }

    /** @return array<string, mixed> */
    public static function present(stdClass $invoice): array
    {
        return [
            'id' => $invoice->id,
            'status' => $invoice->status === 'pending' && $invoice->expires_at !== null && Carbon::parse($invoice->expires_at)->isPast()
                ? 'expired' : $invoice->status,
            'amount' => (int) $invoice->amount,
            'base_amount' => (int) $invoice->base_amount,
            'discount_percent' => (int) $invoice->discount_percent,
            'period' => $invoice->period,
            'plan' => Plan::query()->whereKey($invoice->plan_id)->value('code'),
            'qr_string' => $invoice->status === 'pending' ? $invoice->qr_string : null,
            'qr_url' => $invoice->status === 'pending' ? $invoice->qr_url : null,
            'expires_at' => $invoice->expires_at === null ? null : Carbon::parse($invoice->expires_at)->toIso8601String(),
            'paid_at' => $invoice->paid_at === null ? null : Carbon::parse($invoice->paid_at)->toIso8601String(),
        ];
    }
}
