<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\PersonalAccessToken;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Owner mengeluarkan tablet yang sedang dipakai dari usahanya (mis. tablet mau dipakai usaha lain,
 * atau dijual). Tablet dicabut permanen: token perangkat & semua sesi login di tablet ini dihapus.
 * Data transaksi tetap di server. Untuk memakai tablet lagi, daftarkan ulang (Masuk / Daftar).
 */
class DeviceUnregisterController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $device = $request->attributes->get('device');

        DB::transaction(function () use ($device) {
            $device->forceFill(['revoked_at' => now()])->save();
            $device->tokens()->delete();
            PersonalAccessToken::query()->where('device_id', $device->id)->delete();
        });

        Audit::record('device.unregistered', $device, after: ['code' => $device->code, 'name' => $device->name]);

        return response()->json(['message' => 'Tablet dikeluarkan dari usaha.']);
    }
}
