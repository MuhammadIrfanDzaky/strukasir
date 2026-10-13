<?php

namespace App\Services;

use App\Enums\Role;
use App\Models\Outlet;
use App\Models\Plan;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

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
        array $profile = [],
        ?string $receiptHeader = null,
    ): Tenant {
        return DB::transaction(function () use ($code, $name, $ownerName, $ownerEmail, $ownerPassword, $ownerPin, $planCode, $profile, $receiptHeader) {
            $tenant = new Tenant(['code' => $code, 'name' => $name, 'timezone' => 'Asia/Jakarta']);
            $tenant->plan_id = Plan::where('code', $planCode)->firstOrFail()->id;
            // Profil usaha (pendaftaran mandiri): di luar $fillable, diisi eksplisit di sini saja.
            foreach (['sector', 'sector_other', 'sales_mode', 'outlet_count', 'phone', 'province_code', 'regency_code', 'terms_accepted_at'] as $key) {
                if (array_key_exists($key, $profile)) {
                    $tenant->{$key} = $profile[$key];
                }
            }
            $tenant->save();

            $this->context->run($tenant->id, function () use ($tenant, $name, $ownerName, $ownerEmail, $ownerPassword, $ownerPin, $receiptHeader) {
                // Outlet utama (O1) membawa alamat & no HP dari form daftar (tampil di Pengaturan → Outlet).
                $outlet = new Outlet([
                    'name' => mb_substr($name, 0, 60),
                    'address' => $receiptHeader !== null ? mb_substr($receiptHeader, 0, 160) : null,
                    'phone' => $tenant->phone,
                ]);
                $outlet->code = 'O1';
                $outlet->save();

                (new TenantSetting([
                    'receipt_name' => mb_substr($name, 0, 40),
                    'receipt_header' => $receiptHeader,
                    'receipt_footer' => 'Terima kasih!',
                ]))->save();

                $owner = new User(['name' => $ownerName, 'email' => strtolower($ownerEmail)]);
                $owner->role = Role::Owner;
                $owner->password = $ownerPassword;
                $owner->setPin($ownerPin);
                $owner->save();
            });

            return $tenant;
        });
    }

    /** Kode unik dari nama usaha, mis. "Kopi Kenangan Mantan" → "kopi-kenangan-mantan-7k2p". */
    public function uniqueCode(string $name): string
    {
        $base = Str::limit(Str::slug($name), 30, '') ?: 'kedai';
        do {
            $code = $base.'-'.Str::lower(Str::random(4));
        } while (Tenant::where('code', $code)->exists());

        return $code;
    }
}
