<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Requests\RegisterDeviceRequest;
use App\Models\Device;
use App\Models\Tenant;
use App\Models\User;
use App\Support\Audit;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * Owner mendaftarkan tablet sekali dengan email + password. Tablet menyimpan token perangkat;
 * setelah itu kasir cukup login dengan PIN.
 */
class DeviceRegistrationController extends Controller
{
    public function __invoke(RegisterDeviceRequest $request, TenantContext $context): JsonResponse
    {
        $owner = User::query()->where('email', strtolower((string) $request->input('email')))->first();
        $invalid = response()->json(['message' => 'Email atau password salah.'], 422);

        if ($owner === null || $owner->role !== Role::Owner || ! $owner->active || $owner->password === null) {
            Hash::make('timing-equalizer'); // samakan waktu respons dengan jalur cek password

            return $invalid;
        }

        return $context->run($owner->tenant_id, function () use ($owner, $request, $invalid) {
            if ($owner->isLocked()) {
                return response()->json([
                    'message' => 'Akun terkunci sementara karena terlalu banyak percobaan gagal.',
                    'locked_until' => $owner->locked_until->toIso8601String(),
                ], 423);
            }

            if (! Hash::check((string) $request->input('password'), $owner->password)) {
                $owner->registerFailedAttempt();
                Audit::record('auth.password_failed', $owner, user: $owner);

                return $invalid;
            }

            $tenant = Tenant::findOrFail($owner->tenant_id);
            if (! $tenant->isActive()) {
                return response()->json(['message' => 'Akun kedai tidak aktif.'], 403);
            }

            $owner->clearFailedAttempts();

            [$device, $token] = DB::transaction(function () use ($tenant, $request) {
                // Kunci baris tenant agar kode perangkat (T1, T2, ...) tidak bentrok.
                Tenant::query()->whereKey($tenant->id)->lockForUpdate()->first();

                $clientId = $request->input('device_id');
                $device = $clientId ? Device::query()->find($clientId) : null;

                if ($device?->isRevoked()) {
                    abort(409, 'Tablet ini sudah dicabut. Hapus data aplikasi lalu daftarkan sebagai tablet baru.');
                }

                if ($device) {
                    $device->tokens()->delete(); // kiriman ulang: tablet sama, token lama diganti
                } else {
                    $device = new Device(['name' => (string) $request->input('device_name')]);
                    if ($clientId) {
                        $device->id = $clientId;
                    }
                    $device->code = 'T'.(Device::query()->count() + 1);
                    $device->save();
                }

                return [$device, $device->createToken('device:'.$device->code, ['device'])];
            });

            Audit::record('device.registered', $device, after: ['code' => $device->code, 'name' => $device->name],
                user: $owner, device: $device);

            return response()->json([
                'token' => $token->plainTextToken,
                'device' => ['id' => $device->id, 'code' => $device->code, 'name' => $device->name],
                'tenant' => ['id' => $tenant->id, 'name' => $tenant->name],
            ], 201);
        });
    }
}
