<?php

namespace App\Support;

use App\Enums\Role;
use App\Models\Tenant;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Closure;
use Illuminate\Mail\Mailable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Kirim email ke owner usaha. Dikirim setelah transaksi DB selesai (data sudah pasti tersimpan), dan
 * kegagalan SMTP hanya dicatat — tidak pernah membatalkan pembayaran / pendaftaran yang memicunya.
 */
final class OwnerMailer
{
    /** @param Closure(User $owner, Tenant $tenant): ?Mailable $build null = lewati owner ini */
    public static function send(string $tenantId, Closure $build): void
    {
        DB::afterCommit(function () use ($tenantId, $build) {
            $tenant = Tenant::query()->find($tenantId);
            if ($tenant === null) {
                return;
            }
            $owners = app(TenantContext::class)->run($tenantId, fn () => User::query()
                ->where('role', Role::Owner)->where('active', true)->whereNotNull('email')->get());
            foreach ($owners as $owner) {
                try {
                    $mail = $build($owner, $tenant);
                    if ($mail !== null) {
                        Mail::to($owner->email)->send($mail);
                    }
                } catch (Throwable $e) {
                    report($e);
                }
            }
        });
    }
}
