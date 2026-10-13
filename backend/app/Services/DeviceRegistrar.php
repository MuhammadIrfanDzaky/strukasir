<?php

namespace App\Services;

use App\Models\Device;
use App\Models\Outlet;
use App\Models\Tenant;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\NewAccessToken;

/**
 * Daftarkan tablet ke kedai dan terbitkan token perangkat. Dipakai pendaftaran tablet oleh owner
 * dan pendaftaran usaha baru (tablet pertama). Harus dipanggil di dalam konteks tenant.
 */
class DeviceRegistrar
{
    /** @return array{0: Device, 1: NewAccessToken} */
    public function register(Tenant $tenant, ?string $clientId, ?string $name, ?string $outletId = null): array
    {
        return DB::transaction(function () use ($tenant, $clientId, $name, $outletId) {
            // Kunci baris tenant agar kode perangkat (T1, T2, ...) tidak bentrok.
            Tenant::query()->whereKey($tenant->id)->lockForUpdate()->first();

            $device = $clientId ? Device::query()->find($clientId) : null;

            if ($device?->isRevoked()) {
                abort(409, 'Tablet ini sudah dicabut. Hapus data aplikasi lalu daftarkan sebagai tablet baru.');
            }

            if ($device) {
                $device->tokens()->delete(); // kiriman ulang: tablet sama, token lama diganti
                if ($outletId !== null && $outletId !== $device->outlet_id) {
                    app(OutletService::class)->moveDevice($device, $outletId);
                }
            } else {
                app(SubscriptionService::class)->assertLimit('devices', Device::query()->whereNull('revoked_at')->count());
                $number = Device::query()->count() + 1;
                // Nama opsional: tanpa isian → "Tablet 2" dst. (bisa diganti owner nanti).
                $device = new Device(['name' => trim((string) $name) !== '' ? trim((string) $name) : "Tablet {$number}"]);
                if ($clientId) {
                    $device->id = $clientId;
                }
                $device->code = 'T'.$number;
                $device->outlet_id = $outletId; // null → outlet utama
                $device->save();
            }

            return [$device, $device->createToken('device:'.$device->code, ['device'])];
        });
    }

    /** Bentuk respons yang sama untuk semua jalur pendaftaran tablet. */
    public static function response(Tenant $tenant, Device $device, NewAccessToken $token): array
    {
        return [
            'token' => $token->plainTextToken,
            'device' => ['id' => $device->id, 'code' => $device->code, 'name' => $device->name,
                'outlet' => Outlet::query()->find($device->outlet_id)?->only(['id', 'name'])],
            'tenant' => ['id' => $tenant->id, 'name' => $tenant->name],
        ];
    }
}
