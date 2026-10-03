<?php

namespace App\Console\Commands;

use App\Enums\Role;
use App\Models\PersonalAccessToken;
use App\Models\User;
use App\Support\Audit;
use App\Support\Tenancy\TenantContext;
use Illuminate\Console\Command;
use Illuminate\Support\Str;

/**
 * Reset password (dan opsional PIN) owner oleh developer — pengganti "lupa password" di v1
 * yang belum punya email. Semua sesi owner dicabut dan aksinya tercatat di audit log.
 */
class ResetOwnerPassword extends Command
{
    protected $signature = 'pos:reset-owner-password {email} {--pin : Reset PIN juga}';

    protected $description = 'Reset password owner (dan PIN), cabut semua sesinya';

    public function handle(TenantContext $context): int
    {
        $owner = User::where('email', strtolower($this->argument('email')))->first();
        if ($owner === null || $owner->role !== Role::Owner) {
            $this->error('Owner dengan email itu tidak ditemukan.');

            return self::FAILURE;
        }

        $password = Str::password(16, symbols: false);
        $pin = $this->option('pin') ? (string) random_int(100000, 999999) : null;

        $context->run($owner->tenant_id, function () use ($owner, $password, $pin) {
            $owner->password = $password;
            if ($pin !== null) {
                $owner->setPin($pin);
            }
            $owner->failed_attempts = 0;
            $owner->locked_until = null;
            $owner->save();

            PersonalAccessToken::query()
                ->where('tokenable_type', $owner->getMorphClass())
                ->where('tokenable_id', $owner->id)
                ->delete();

            Audit::record('owner.credentials_reset', $owner, after: ['pin_reset' => $pin !== null], user: $owner);
        });

        $this->warn('Kredensial baru (ditampilkan sekali):');
        $this->line("  Password: {$password}");
        if ($pin !== null) {
            $this->line("  PIN     : {$pin}");
        }

        return self::SUCCESS;
    }
}
