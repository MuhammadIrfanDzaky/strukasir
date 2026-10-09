<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\Outlet;
use App\Services\OutletService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Pengaturan → Outlet (owner): daftar outlet & tabletnya, tambah/ubah outlet, pindah tablet. */
class OutletController extends Controller
{
    public function __construct(private readonly OutletService $outlets) {}

    public function index(Request $request): JsonResponse
    {
        $devices = Device::query()->whereNull('revoked_at')->orderBy('code')->get()->groupBy('outlet_id');
        $current = $request->attributes->get('device');

        return response()->json(['data' => [
            'enabled' => $this->outlets->enabled(),
            'outlets' => Outlet::query()->orderByDesc('active')->orderByRaw('length(code), code')->get()->map(fn (Outlet $o) => [
                ...$o->present(),
                'devices' => ($devices[$o->id] ?? collect())->map(fn (Device $d) => [
                    'id' => $d->id, 'code' => $d->code, 'name' => $d->name,
                    'last_seen_at' => $d->last_seen_at?->toIso8601String(), 'current' => $d->id === $current?->id,
                ])->values(),
            ])->values(),
        ]]);
    }

    public function save(Request $request, ?Outlet $outlet = null): JsonResponse
    {
        $request->merge(['name' => trim((string) $request->input('name'))]);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:60', 'regex:/\S/',
                Rule::unique('outlets', 'name')->where('tenant_id', $request->user()->tenant_id)->ignore($outlet?->id)],
            'address' => ['nullable', 'string', 'max:160'],
            'phone' => ['nullable', 'string', 'max:20', 'regex:/^[0-9+\-\s()]*$/'],
            'active' => ['sometimes', 'boolean'],
        ], ['name.unique' => 'Nama outlet sudah dipakai.']);
        $saved = $this->outlets->save($data, $outlet);

        return response()->json(['data' => $saved->present()], $outlet ? 200 : 201);
    }

    public function moveDevice(Request $request, Device $device): JsonResponse
    {
        abort_if($device->isRevoked(), 404);
        $data = $request->validate(['outlet_id' => ['required', 'uuid']]);
        $this->outlets->moveDevice($device, $data['outlet_id']);

        return response()->json(['data' => ['id' => $device->id, 'outlet_id' => $device->outlet_id]]);
    }
}
