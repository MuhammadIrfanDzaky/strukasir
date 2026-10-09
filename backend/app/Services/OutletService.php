<?php

namespace App\Services;

use App\Enums\Feature;
use App\Models\Device;
use App\Models\Outlet;
use App\Models\Tenant;
use App\Support\Audit;
use App\Support\Tenancy\FeatureGate;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\ConflictHttpException;

/**
 * Outlet (fitur `multi_outlet`). Tanpa fitur ini kedai hanya punya satu outlet aktif; outlet lama
 * tetap tersimpan (riwayat) bila fitur dimatikan.
 */
class OutletService
{
    public function enabled(): bool
    {
        return app(FeatureGate::class)->enabled(Feature::MultiOutlet);
    }

    /** @param  array{name: string, address?: ?string, phone?: ?string, active?: bool}  $data */
    public function save(array $data, ?Outlet $outlet = null): Outlet
    {
        return DB::transaction(function () use ($data, $outlet) {
            // Kunci baris tenant: dua simpan bersamaan tidak melewati batas outlet / bentrok kode.
            Tenant::query()->whereKey(app(TenantContext::class)->id())->lockForUpdate()->first();
            $active = $data['active'] ?? true;
            $others = Outlet::query()->where('active', true)->when($outlet, fn ($q) => $q->whereKeyNot($outlet->id))->count();
            if ($active && $others > 0 && ! $this->enabled()) {
                throw ValidationException::withMessages(['name' => 'Fitur multi-outlet tidak aktif untuk paket ini.']);
            }
            if ($outlet?->exists && ! $active && $outlet->active) {
                if ($others === 0) {
                    throw ValidationException::withMessages(['active' => 'Minimal satu outlet harus aktif.']);
                }
                if (Device::query()->where('outlet_id', $outlet->id)->whereNull('revoked_at')->exists()) {
                    throw ValidationException::withMessages(['active' => 'Pindahkan atau keluarkan dulu tablet di outlet ini.']);
                }
            }

            $outlet ??= new Outlet;
            $before = $outlet->exists ? $outlet->present() : null;
            if (! $outlet->exists) {
                // Kode berurutan O1, O2, … (tidak dipakai ulang walau outlet dinonaktifkan).
                $n = Outlet::query()->get(['code'])->map(fn ($o) => (int) substr($o->code, 1))->max() ?? 0;
                $outlet->code = 'O'.($n + 1);
            }
            $outlet->fill([
                'name' => $data['name'],
                'address' => $data['address'] ?? null,
                'phone' => $data['phone'] ?? null,
                'active' => $active,
            ])->save();
            Audit::record($before ? 'outlet.updated' : 'outlet.created', $outlet, $before, $outlet->present());

            return $outlet;
        });
    }

    /** Pindahkan tablet ke outlet lain. Ditolak bila shift tablet masih terbuka (uang laci ikut outlet lama). */
    public function moveDevice(Device $device, string $outletId): void
    {
        $outlet = Outlet::query()->whereKey($outletId)->where('active', true)->first()
            ?? throw ValidationException::withMessages(['outlet_id' => 'Outlet tidak ditemukan atau nonaktif.']);
        if ($outlet->id === $device->outlet_id) {
            return;
        }
        if (app(ShiftService::class)->current($device) !== null) {
            throw new ConflictHttpException("Tutup dulu shift di {$device->name} sebelum pindah outlet.");
        }
        $before = $device->outlet_id;
        $device->forceFill(['outlet_id' => $outlet->id])->save();
        Audit::record('device.moved', $device, ['outlet_id' => $before], ['outlet_id' => $outlet->id, 'outlet' => $outlet->name]);
    }
}
