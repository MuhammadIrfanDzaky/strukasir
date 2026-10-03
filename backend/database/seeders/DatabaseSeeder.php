<?php

namespace Database\Seeders;

use App\Enums\Feature;
use App\Enums\Role;
use App\Models\Plan;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class DatabaseSeeder extends Seeder
{
    public function run(TenantContext $context): void
    {
        $this->seedFeaturesAndPlans();

        if (! app()->isProduction()) {
            $this->seedBerryBrew($context);
        }
    }

    private function seedFeaturesAndPlans(): void
    {
        foreach (Feature::cases() as $feature) {
            DB::table('features')->updateOrInsert(
                ['key' => $feature->value],
                ['description' => $feature->description(), 'updated_at' => now(), 'created_at' => now()],
            );
        }

        // Untuk saat ini satu paket berisi semua fitur v1. Paket berjenjang menyusul saat ada klien ke-2.
        $plan = Plan::firstOrCreate(['code' => 'standard'], ['name' => 'Standard']);
        foreach (Feature::cases() as $feature) {
            DB::table('plan_features')->insertOrIgnore(['plan_id' => $plan->id, 'feature_key' => $feature->value]);
        }
    }

    /** Tenant BerryBrew untuk development. Kredensial dari .env; jika kosong dibuat acak. */
    private function seedBerryBrew(TenantContext $context): void
    {
        if (Tenant::where('code', 'berrybrew')->exists()) {
            $this->command?->info('Tenant berrybrew sudah ada, dilewati.');

            return;
        }

        $tenant = new Tenant(['code' => 'berrybrew', 'name' => 'BerryBrew', 'timezone' => 'Asia/Jakarta']);
        $tenant->plan_id = Plan::where('code', 'standard')->value('id');
        $tenant->save();

        $email = env('SEED_OWNER_EMAIL') ?: 'owner@berrybrew.test';
        $password = env('SEED_OWNER_PASSWORD') ?: Str::password(16, symbols: false);
        $ownerPin = env('SEED_OWNER_PIN') ?: (string) random_int(100000, 999999);
        $cashierPin = env('SEED_CASHIER_PIN') ?: (string) random_int(100000, 999999);

        $context->run($tenant->id, function () use ($email, $password, $ownerPin, $cashierPin) {
            $settings = new TenantSetting(['receipt_name' => 'BerryBrew', 'receipt_footer' => 'Terima kasih!']);
            $settings->save();

            $owner = new User(['name' => 'Owner', 'email' => $email]);
            $owner->role = Role::Owner;
            $owner->password = $password;
            $owner->setPin($ownerPin);
            $owner->save();

            $cashier = new User(['name' => 'Kasir 1']);
            $cashier->role = Role::Cashier;
            $cashier->setPin($cashierPin);
            $cashier->save();
        });

        $this->command?->warn('Kredensial dev BerryBrew (simpan, tidak ditampilkan lagi):');
        $this->command?->line("  Owner  : {$email} / {$password} / PIN {$ownerPin}");
        $this->command?->line("  Kasir 1: PIN {$cashierPin}");
    }
}
