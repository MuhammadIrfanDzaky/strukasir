<?php

namespace App\Console\Commands;

use App\Enums\Role;
use App\Models\User;
use App\Support\Audit;
use App\Support\Tenancy\TenantContext;
use App\Support\TwoFactor;
use Illuminate\Console\Command;

/**
 * Aktifkan / matikan 2FA (TOTP) owner. Setelah aktif, mendaftarkan tablet baru butuh
 * email + password + kode 6 digit dari aplikasi authenticator (SEC-19).
 *
 * Aktivasi dilakukan bersama owner: rahasia ditampilkan sekali, owner memasukkannya ke
 * Google Authenticator / Aegis, lalu menyebutkan satu kode untuk konfirmasi.
 */
class OwnerTwoFactor extends Command
{
    protected $signature = 'pos:owner-2fa {email} {--disable : Matikan 2FA (mis. HP owner hilang)}';

    protected $description = 'Aktifkan atau matikan 2FA owner untuk pendaftaran tablet';

    public function handle(TenantContext $context, TwoFactor $twoFactor): int
    {
        $owner = User::where('email', strtolower($this->argument('email')))->first();
        if ($owner === null || $owner->role !== Role::Owner) {
            $this->error('Owner dengan email itu tidak ditemukan.');

            return self::FAILURE;
        }

        return $context->run($owner->tenant_id, fn () => $this->option('disable')
            ? $this->disable($owner)
            : $this->enable($owner, $twoFactor));
    }

    private function enable(User $owner, TwoFactor $twoFactor): int
    {
        if ($owner->hasTwoFactor() && ! $this->confirm('2FA sudah aktif. Ganti dengan kunci baru?', false)) {
            return self::SUCCESS;
        }

        $secret = $twoFactor->newSecret();
        $this->line('');
        $this->warn('Tambahkan ke aplikasi authenticator owner (ditampilkan sekali):');
        $this->line('  Akun  : Strukasir ('.$owner->email.')');
        $this->line('  Kunci : '.implode(' ', str_split($secret, 4)));
        $this->line('  Atau buat QR dari URI ini: '.$twoFactor->otpauthUri($owner, $secret));
        $this->line('');

        for ($attempt = 1; $attempt <= 3; $attempt++) {
            $code = trim((string) $this->ask('Kode 6 digit yang tampil di aplikasi'));
            $owner->two_factor_last_step = null; // kunci baru: riwayat langkah lama tidak berlaku
            if ($twoFactor->verify($owner, $code, $secret)) {
                $owner->two_factor_secret = $secret;
                $owner->two_factor_confirmed_at = now();
                $owner->save();
                Audit::record('owner.2fa_enabled', $owner, user: $owner);
                $this->info('2FA aktif. Pendaftaran tablet berikutnya meminta kode dari aplikasi ini.');

                return self::SUCCESS;
            }
            $this->error('Kode salah. Pastikan jam HP otomatis, lalu coba kode berikutnya.');
        }

        $this->error('2FA TIDAK diaktifkan.');

        return self::FAILURE;
    }

    private function disable(User $owner): int
    {
        $owner->two_factor_secret = null;
        $owner->two_factor_confirmed_at = null;
        $owner->two_factor_last_step = null;
        $owner->save();
        Audit::record('owner.2fa_disabled', $owner, user: $owner);
        $this->info('2FA owner dimatikan. Aktifkan lagi setelah owner punya HP/aplikasi baru.');

        return self::SUCCESS;
    }
}
