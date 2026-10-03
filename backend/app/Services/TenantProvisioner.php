<?php

namespace App\Services;

use App\Enums\Role;
use App\Models\Plan;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;

/**
 * Membuat kedai baru beserta pengaturan & owner-nya. Dipakai command `pos:create-tenant`
 * (produksi) dan seeder (development).
 */
class TenantProvisioner
{
    public function __construct(private readonly TenantContext $context) {}

    public function create(
        string $code,
        string $name,
        string $ownerName,
        string $ownerEmail,
        string $ownerPassword,
        string $ownerPin,
        string $planCode = 'standard',
    ): Tenant {
        return DB::transaction(function () use ($code, $name, $ownerName, $ownerEmail, $ownerPassword, $ownerPin, $planCode) {
            $tenant = new Tenant(['code' => $code, 'name' => $name, 'timezone' => 'Asia/Jakarta']);
            $tenant->plan_id = Plan::where('code', $planCode)->firstOrFail()->id;
            $tenant->save();

            $this->context->run($tenant->id, function () use ($name, $ownerName, $ownerEmail, $ownerPassword, $ownerPin) {
                (new TenantSetting(['receipt_name' => $name, 'receipt_footer' => 'Terima kasih!']))->save();

                $owner = new User(['name' => $ownerName, 'email' => strtolower($ownerEmail)]);
                $owner->role = Role::Owner;
                $owner->password = $ownerPassword;
                $owner->setPin($ownerPin);
                $owner->save();
            });

            return $tenant;
        });
    }
}
