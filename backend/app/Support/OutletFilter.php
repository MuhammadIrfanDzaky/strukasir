<?php

namespace App\Support;

use App\Enums\Permission;
use App\Models\Outlet;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\ValidationException;

/**
 * Parameter `?outlet=` di daftar & laporan: kosong = outlet tablet ini, `all` = semua outlet,
 * UUID = outlet tertentu. Melihat outlet lain / semua outlet hanya untuk yang boleh melihat laporan.
 */
class OutletFilter
{
    /** @return string|null ID outlet, null = semua outlet */
    public static function resolve(Request $request, ?string $default = 'device'): ?string
    {
        $value = $request->input('outlet');
        $device = $request->attributes->get('device');
        if ($value === null || $value === '') {
            return $default === 'device' ? $device?->outlet_id : null;
        }
        if ($value !== $device?->outlet_id) {
            abort_unless(Gate::allows(Permission::ReportsView->value), 403, 'Hanya owner yang bisa melihat outlet lain.');
        }
        if ($value === 'all') {
            return null;
        }
        if (! is_string($value) || ! Outlet::query()->whereKey(preg_match('/^[0-9a-f-]{36}$/i', $value) ? $value : null)->exists()) {
            throw ValidationException::withMessages(['outlet' => 'Outlet tidak ditemukan.']);
        }

        return $value;
    }
}
