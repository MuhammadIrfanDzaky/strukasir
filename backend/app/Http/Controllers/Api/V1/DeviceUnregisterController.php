<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\PersonalAccessToken;
use App\Models\User;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Owner mengeluarkan tablet dari usahanya (mis. tablet mau dipakai usaha lain, dijual, hilang, rusak,
 * atau aplikasinya di-reset). Tablet dicabut permanen: token perangkat & semua sesi login di tablet itu
 * dihapus, kuota tablet paket kembali. Data transaksi tetap di server. Untuk memakai lagi, daftarkan ulang.
 */
class DeviceUnregisterController extends Controller
{
    /** Tablet yang sedang dipakai. */
    public function __invoke(Request $request): JsonResponse
    {
        self::revoke($request->attributes->get('device'), $request->user());

        return response()->json(['message' => 'Tablet dikeluarkan dari usaha.']);
    }

    /** Tablet lain, dari daftar tablet di halaman Outlet. */
    public function other(Request $request, Device $device): JsonResponse
    {
        abort_if($device->isRevoked(), 404);
        if ($device->id === $request->attributes->get('device')?->id) {
            throw ValidationException::withMessages([
                'device' => 'Ini tablet yang sedang dipakai. Gunakan Pengaturan → Keluarkan tablet dari usaha.',
            ]);
        }
        self::revoke($device, $request->user());

        return response()->json(['message' => "Tablet {$device->code} dikeluarkan."]);
    }

    private static function revoke(Device $device, ?User $by): void
    {
        DB::transaction(function () use ($device) {
            $device->forceFill(['revoked_at' => now()])->save();
            $device->tokens()->delete();
            PersonalAccessToken::query()->where('device_id', $device->id)->delete();
        });

        Audit::record('device.unregistered', $device, after: ['code' => $device->code, 'name' => $device->name], user: $by);
    }
}
