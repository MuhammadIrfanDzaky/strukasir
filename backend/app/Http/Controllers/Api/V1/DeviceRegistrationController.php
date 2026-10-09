<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Requests\RegisterDeviceRequest;
use App\Models\Device;
use App\Models\Outlet;
use App\Models\Tenant;
use App\Models\User;
use App\Services\DeviceRegistrar;
use App\Support\Audit;
use App\Support\Tenancy\TenantContext;
use App\Support\TwoFactor;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Hash;

/**
 * Owner mendaftarkan tablet sekali dengan email + password (+ kode 2FA bila aktif). Tablet menyimpan token perangkat;
 * setelah itu kasir cukup login dengan PIN.
 */
class DeviceRegistrationController extends Controller
{
    public function __invoke(
        RegisterDeviceRequest $request,
        TenantContext $context,
        TwoFactor $twoFactor,
        DeviceRegistrar $registrar,
    ): JsonResponse {
        $owner = User::query()->where('email', strtolower((string) $request->input('email')))->first();
        $invalid = response()->json(['message' => 'Email atau password salah.'], 422);

        if ($owner === null || $owner->role !== Role::Owner || ! $owner->active || $owner->password === null) {
            Hash::make('timing-equalizer'); // samakan waktu respons dengan jalur cek password

            return $invalid;
        }

        return $context->run($owner->tenant_id, function () use ($owner, $request, $invalid, $twoFactor, $registrar) {
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

            // Beberapa outlet: tanyakan outlet tablet baru dulu (sebelum kode 2FA dipakai, supaya kode yang
            // sama masih berlaku saat dikirim ulang bersama pilihan outlet).
            $outlets = Outlet::query()->where('active', true)->orderByRaw('length(code), code')->get();
            $outletId = $request->input('outlet_id');
            $known = $request->input('device_id') ? Device::query()->find($request->input('device_id')) : null;
            if ($outletId === null && $known === null && $outlets->count() > 1) {
                return response()->json([
                    'message' => 'Pilih outlet untuk tablet ini.',
                    'errors' => ['outlet_id' => ['Pilih outlet untuk tablet ini.']],
                    'outlets' => $outlets->map(fn (Outlet $o) => ['id' => $o->id, 'name' => $o->name, 'address' => $o->address])->values(),
                ], 422);
            }
            if ($outletId !== null && ! $outlets->contains('id', $outletId)) {
                return response()->json(['message' => 'Outlet tidak ditemukan.', 'errors' => ['outlet_id' => ['Outlet tidak ditemukan.']]], 422);
            }

            // 2FA (SEC-19): password benar tapi kode belum dikirim → minta kode, bukan percobaan gagal.
            if ($owner->hasTwoFactor()) {
                $otp = trim((string) $request->input('otp'));
                if ($otp === '') {
                    return response()->json([
                        'message' => 'Masukkan kode 2FA dari aplikasi authenticator.',
                        'errors' => ['otp' => ['Masukkan kode 6 digit dari aplikasi authenticator.']],
                    ], 422);
                }
                if (! $twoFactor->verify($owner, $otp)) {
                    $owner->registerFailedAttempt();
                    Audit::record('auth.otp_failed', $owner, user: $owner);

                    return response()->json([
                        'message' => 'Kode 2FA salah atau sudah dipakai.',
                        'errors' => ['otp' => ['Kode 2FA salah atau sudah dipakai. Tunggu kode berikutnya.']],
                    ], 422);
                }
            }

            $tenant = Tenant::findOrFail($owner->tenant_id);
            if (! $tenant->isActive()) {
                return response()->json(['message' => 'Akun kedai tidak aktif.'], 403);
            }

            $owner->clearFailedAttempts();

            [$device, $token] = $registrar->register($tenant, $request->input('device_id'), $request->input('device_name'), $outletId);

            Audit::record('device.registered', $device, after: ['code' => $device->code, 'name' => $device->name],
                user: $owner, device: $device);

            return response()->json(DeviceRegistrar::response($tenant, $device, $token), 201);
        });
    }
}
