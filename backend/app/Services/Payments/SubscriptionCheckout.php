<?php

namespace App\Services\Payments;

use App\Enums\Role;
use App\Models\Plan;
use App\Models\Tenant;
use App\Models\User;
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

/**
 * Bayar paket lewat Mayar (invoice, QRIS). Harga & diskon dihitung server dan dikunci di tagihan; tagihan
 * dianggap lunas hanya bila status dari API Mayar (diambil server) = paid dengan jumlah yang sama.
 * Webhook & polling app memakai jalur yang sama (`sync`) dan idempotent per tagihan.
 */
class SubscriptionCheckout
{
    public function __construct(private readonly Mayar $mayar) {}

    public function enabled(): bool
    {
        return $this->mayar->enabled();
    }

    public function create(Tenant $tenant, Plan $plan, string $period): stdClass
    {
        if (! $plan->public || $plan->code === PlanCatalog::FREE) {
            throw ValidationException::withMessages(['plan' => 'Pilih paket berbayar.']);
        }
        // Tagihan yang masih berlaku untuk paket & periode sama dipakai ulang (tidak menumpuk tagihan).
        $open = DB::table('subscription_invoices')->where('tenant_id', $tenant->id)->where('status', 'pending')
            ->where('plan_id', $plan->id)->where('period', $period)->where('expires_at', '>', now()->addMinutes(2))
            ->orderByDesc('created_at')->first();
        $quote = app(ReferralService::class)->quote($tenant, $plan, $period);
        if ($open !== null && (int) $open->amount === $quote['amount']) {
            return $open;
        }

        $id = (string) Str::uuid7();
        $orderId = 'STK-'.strtoupper(Str::random(6)).'-'.now()->format('ymdHis');
        $expiresAt = now()->addMinutes((int) config('services.mayar.expiry_minutes', 30));
        $owner = app(TenantContext::class)->run($tenant->id, fn () => User::query()->where('role', Role::Owner)->orderBy('created_at')->first());
        $months = PlanCatalog::months($period);
        $invoice = $this->mayar->createInvoice(
            customer: [
                'name' => $owner?->name ?? $tenant->name,
                'email' => $owner?->email ?? 'owner@strukasir.id',
                // Wajib di Mayar; usaha tanpa no HP memakai nomor kosong (tidak dipakai untuk menghubungi).
                'mobile' => $tenant->phone ?: '080000000000',
            ],
            amount: $quote['amount'],
            description: "Strukasir {$plan->name} {$months} bulan - {$tenant->name}",
            expiresAt: $expiresAt->copy()->utc(),
            extra: ['order_id' => $orderId, 'tenant' => $tenant->code],
        );

        DB::table('subscription_invoices')->insert([
            'id' => $id, 'tenant_id' => $tenant->id, 'plan_id' => $plan->id, 'period' => $period,
            'base_amount' => $quote['base'], 'discount_percent' => $quote['percent'], 'discount_reason' => $quote['reason'],
            'amount' => $quote['amount'], 'gateway' => 'mayar', 'order_id' => $orderId, 'gateway_ref' => $invoice['id'],
            'status' => 'pending', 'pay_url' => $invoice['link'],
            'expires_at' => $invoice['expires_at'] ?? $expiresAt,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        Audit::record('plan.checkout', $tenant, after: ['plan' => $plan->code, 'period' => $period, 'amount' => $quote['amount'], 'order_id' => $orderId]);

        return DB::table('subscription_invoices')->where('id', $id)->first();
    }

    /** Cocokkan status tagihan dengan Mayar; lunas → paket aktif (sekali saja). */
    public function sync(stdClass $invoice): stdClass
    {
        if ($invoice->status !== 'pending' || $invoice->gateway_ref === null) {
            return $invoice;
        }
        $status = $this->mayar->invoice($invoice->gateway_ref);
        if ($status === null) {
            return $invoice;
        }

        return $this->apply($invoice->id, $status);
    }

    /** @param array{status: string, amount: int} $status hasil GET invoice Mayar */
    private function apply(string $invoiceId, array $status): stdClass
    {
        return DB::transaction(function () use ($invoiceId, $status) {
            $invoice = DB::table('subscription_invoices')->where('id', $invoiceId)->lockForUpdate()->first();
            if ($invoice->status !== 'pending') {
                return $invoice; // webhook/polling ganda
            }
            $next = Mayar::mapStatus($status['status']);
            if ($next === 'paid' && $status['amount'] !== (int) $invoice->amount) {
                report(new \RuntimeException("Jumlah Mayar tidak cocok untuk {$invoice->order_id}"));

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
                // Webhook datang tanpa konteks usaha: catat audit di usaha pemilik tagihan.
                app(TenantContext::class)->run($tenant->id, fn () => Audit::record('plan.paid', $tenant, after: [
                    'plan' => $plan->code, 'period' => $invoice->period, 'amount' => (int) $invoice->amount, 'order_id' => $invoice->order_id,
                ]));
            }
            DB::table('subscription_invoices')->where('id', $invoiceId)->update($update);

            return DB::table('subscription_invoices')->where('id', $invoiceId)->first();
        });
    }

    /**
     * Webhook Mayar (tanpa tanda tangan): hanya pemicu untuk mencocokkan ulang ke API Mayar. Tagihan yang
     * cocok dengan `data.productId` dicek dulu; bila tidak ketemu, semua tagihan yang masih menunggu (24 jam).
     *
     * @param  array<string, mixed>  $payload
     */
    public function handleWebhook(array $payload): void
    {
        $ref = (string) data_get($payload, 'data.productId', '');
        $pending = DB::table('subscription_invoices')->where('status', 'pending')->where('created_at', '>', now()->subDay());
        $matched = $ref !== '' ? (clone $pending)->where('gateway_ref', $ref)->get() : collect();
        foreach ($matched->isNotEmpty() ? $matched : $pending->orderByDesc('created_at')->limit(50)->get() as $invoice) {
            $this->sync($invoice);
        }
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
            // Halaman bayar Mayar (QRIS); hanya selama masih menunggu.
            'pay_url' => $invoice->status === 'pending' ? $invoice->pay_url : null,
            'expires_at' => $invoice->expires_at === null ? null : Carbon::parse($invoice->expires_at)->toIso8601String(),
            'paid_at' => $invoice->paid_at === null ? null : Carbon::parse($invoice->paid_at)->toIso8601String(),
        ];
    }
}
