<?php

namespace App\Console\Commands;

use App\Mail\PlanReminderMail;
use App\Models\Tenant;
use App\Support\OwnerMailer;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Email pengingat paket ke owner (dijadwalkan harian): 3 hari & 1 hari sebelum berakhir, dan saat sudah
 * berakhir (maks. 3 hari lalu). Tiap jenis dikirim sekali per tanggal akhir paket (`tenant_notices`).
 */
class SendPlanReminders extends Command
{
    protected $signature = 'pos:plan-reminders';

    protected $description = 'Kirim email pengingat masa coba / paket yang akan atau sudah berakhir';

    public function handle(): int
    {
        $sent = 0;
        $tenants = Tenant::query()->with('plan')->whereNotNull('plan_ends_at')
            ->whereBetween('plan_ends_at', [now()->subDays(3), now()->addDays(3)])->get();

        foreach ($tenants as $tenant) {
            $hours = now()->diffInHours($tenant->plan_ends_at, false);
            [$kind, $days] = match (true) {
                $hours <= 0 => ['plan_expired', 0],
                $hours <= 24 => ['plan_reminder_1d', 1],
                $hours <= 72 => ['plan_reminder_3d', (int) ceil($hours / 24)],
                default => [null, null],
            };
            if ($kind === null) {
                continue;
            }
            $added = DB::table('tenant_notices')->insertOrIgnore([
                'id' => (string) Str::uuid7(), 'tenant_id' => $tenant->id, 'kind' => $kind,
                'ref' => $tenant->plan_ends_at->toIso8601String(), 'created_at' => now(),
            ]);
            if ($added === 0) {
                continue; // sudah pernah dikirim untuk tanggal akhir ini
            }
            OwnerMailer::send($tenant->id, fn ($owner, $t) => new PlanReminderMail(
                ownerName: $owner->name, businessName: $t->name, planName: $t->plan->name,
                status: $t->plan_status, endsAt: $t->plan_ends_at, daysLeft: $days,
            ));
            $sent++;
        }
        $this->info("Pengingat terkirim ke {$sent} usaha.");

        return self::SUCCESS;
    }
}
