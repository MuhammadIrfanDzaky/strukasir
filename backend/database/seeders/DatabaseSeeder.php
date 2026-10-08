<?php

namespace Database\Seeders;

use App\Enums\Role;
use App\Models\Tenant;
use App\Models\User;
use App\Services\TenantProvisioner;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class DatabaseSeeder extends Seeder
{
    public function run(TenantContext $context, TenantProvisioner $provisioner): void
    {
        $this->call(FeatureSeeder::class);

        if (! app()->isProduction()) {
            $this->seedBerryBrew($context, $provisioner);
        }
    }

    /** Tenant BerryBrew untuk development. Kredensial dari .env; jika kosong dibuat acak. */
    private function seedBerryBrew(TenantContext $context, TenantProvisioner $provisioner): void
    {
        if (Tenant::where('code', 'berrybrew')->exists()) {
            $this->command?->info('Tenant berrybrew sudah ada, dilewati.');

            return;
        }

        $email = env('SEED_OWNER_EMAIL') ?: 'owner@berrybrew.test';
        $password = env('SEED_OWNER_PASSWORD') ?: Str::password(16, symbols: false);
        $ownerPin = env('SEED_OWNER_PIN') ?: (string) random_int(100000, 999999);
        $cashierPin = env('SEED_CASHIER_PIN') ?: (string) random_int(100000, 999999);

        $tenant = $provisioner->create('berrybrew', 'BerryBrew', 'Owner', $email, $password, $ownerPin);

        $context->run($tenant->id, function () use ($cashierPin) {
            $cashier = new User(['name' => 'Kasir 1']);
            $cashier->role = Role::Cashier;
            $cashier->setPin($cashierPin);
            $cashier->save();

            (new BerryBrewMenuSeeder)->seedMenu();
        });

        $this->command?->info('Menu asli BerryBrew dibuat (BerryBrewMenuSeeder).');
        $this->command?->warn('Kredensial dev BerryBrew (simpan, tidak ditampilkan lagi):');
        $this->command?->line("  Owner  : {$email} / {$password} / PIN {$ownerPin}");
        $this->command?->line("  Kasir 1: PIN {$cashierPin}");
    }
}
