<?php

namespace App\Console\Commands;

use App\Models\Plan;
use App\Models\Tenant;
use App\Services\SubscriptionService;
use Illuminate\Console\Command;

/** Pembayaran paket diterima (transfer/QRIS manual) → aktifkan paket usaha sampai akhir periode. */
class ActivatePlan extends Command
{
    protected $signature = 'pos:activate-plan {tenant : Kode usaha} {plan : gratis|mulai|tumbuh|juragan} {--period=month : month|year}';

    protected $description = 'Aktifkan paket berbayar usaha setelah pembayaran diterima';

    public function handle(SubscriptionService $subscriptions): int
    {
        $tenant = Tenant::query()->where('code', $this->argument('tenant'))->first();
        $plan = Plan::query()->where('code', $this->argument('plan'))->first();
        $period = (string) $this->option('period');
        if ($tenant === null || $plan === null || ! in_array($period, ['month', 'year'], true)) {
            $this->error('Usaha, paket, atau periode tidak dikenal.');

            return self::FAILURE;
        }

        $subscriptions->activate($tenant, $plan, $period);
        $this->info("{$tenant->name}: paket {$plan->name} aktif sampai {$tenant->plan_ends_at->timezone('Asia/Jakarta')->format('d M Y H:i')} WIB.");

        return self::SUCCESS;
    }
}
