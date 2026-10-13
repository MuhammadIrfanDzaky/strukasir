<?php

namespace App\Console\Commands;

use App\Models\Plan;
use App\Models\Tenant;
use App\Services\SubscriptionService;
use App\Support\PlanCatalog;
use Illuminate\Console\Command;

/** Pembayaran paket diterima (transfer/QRIS manual) → aktifkan paket usaha sampai akhir periode. */
class ActivatePlan extends Command
{
    protected $signature = 'pos:activate-plan {tenant : Kode usaha} {plan : gratis|mulai|tumbuh|juragan} {--period=month : month|quarter|half|year (1/3/6/12 bulan)}';

    protected $description = 'Aktifkan paket berbayar usaha setelah pembayaran diterima';

    public function handle(SubscriptionService $subscriptions): int
    {
        $tenant = Tenant::query()->where('code', $this->argument('tenant'))->first();
        $plan = Plan::query()->where('code', $this->argument('plan'))->first();
        $period = (string) $this->option('period');
        if ($tenant === null || $plan === null || ! array_key_exists($period, PlanCatalog::PERIODS)) {
            $this->error('Usaha, paket, atau periode tidak dikenal.');

            return self::FAILURE;
        }

        $quote = $subscriptions->activate($tenant, $plan, $period);
        $note = $quote['percent'] > 0 ? " (harga normal Rp{$quote['base']}, diskon {$quote['percent']}% {$quote['reason']})" : '';
        $this->info("Tagihan: Rp{$quote['amount']}{$note}");
        $this->info("{$tenant->name}: paket {$plan->name} aktif sampai {$tenant->plan_ends_at->timezone('Asia/Jakarta')->format('d M Y H:i')} WIB.");

        return self::SUCCESS;
    }
}
