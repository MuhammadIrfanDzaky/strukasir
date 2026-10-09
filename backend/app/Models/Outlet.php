<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Outlet / cabang (lihat migrasi create_outlets). Tidak dihapus; gunakan `active=false`. */
class Outlet extends Model
{
    use BelongsToTenant, HasUuids;

    protected $fillable = ['name', 'address', 'phone', 'active'];

    protected function casts(): array
    {
        return ['active' => 'boolean'];
    }

    public function devices(): HasMany
    {
        return $this->hasMany(Device::class);
    }

    /** Outlet pertama (O1) kedai aktif; dibuat bila belum ada (kedai baru). */
    public static function main(): self
    {
        $outlet = self::query()->orderByRaw('length(code), code')->first();
        if ($outlet !== null) {
            return $outlet;
        }
        $tenant = Tenant::query()->findOrFail(app(TenantContext::class)->id());
        $outlet = new self(['name' => mb_substr($tenant->name, 0, 60)]);
        $outlet->code = 'O1';
        $outlet->save();

        return $outlet;
    }

    /** @return array<string, mixed> */
    public function present(): array
    {
        return ['id' => $this->id, 'code' => $this->code, 'name' => $this->name, 'address' => $this->address, 'phone' => $this->phone, 'active' => $this->active];
    }
}
