<?php

namespace App\Services;

use App\Models\Device;
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
    public function register(Tenant $tenant, ?string $clientId, ?string $name): array
    {
        return DB::transaction(function () use ($tenant, $clientId, $name) {
            // Kunci baris tenant agar kode perangkat (T1, T2, ...) tidak bentrok.
            Tenant::query()->whereKey($tenant->id)->lockForUpdate()->first();

            $device = $clientId ? Device::query()->find($clientId) : null;

            if ($device?->isRevoked()) {
                abort(409, 'Tablet ini sudah dicabut. Hapus data aplikasi lalu daftarkan sebagai tablet baru.');
            }

            if ($device) {
                $device->tokens()->delete(); // kiriman ulang: tablet sama, token lama diganti
            } else {
                $number = Device::query()->count() + 1;
                // Nama opsional: tanpa isian → "Tablet 2" dst. (bisa diganti owner nanti).
                $device = new Device(['name' => trim((string) $name) !== '' ? trim((string) $name) : "Tablet {$number}"]);
                if ($clientId) {
                    $device->id = $clientId;
                }
                $device->code = 'T'.$number;
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
            'device' => ['id' => $device->id, 'code' => $device->code, 'name' => $device->name],
            'tenant' => ['id' => $tenant->id, 'name' => $tenant->name],
        ];
    }
}
