<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Laravel\Sanctum\HasApiTokens;

/**
 * Tablet kasir yang didaftarkan owner. Token perangkat hanya boleh melihat daftar staf
 * dan melakukan login PIN; semua operasi lain memakai token user yang terikat ke perangkat ini.
 */
class Device extends Model
{
    use BelongsToTenant, HasApiTokens, HasFactory, HasUuids;

    protected $fillable = ['name'];

    protected function casts(): array
    {
        return [
            'last_seen_at' => 'datetime',
            'revoked_at' => 'datetime',
        ];
    }

    public function requiresTenantContext(): bool
    {
        return false;
    }

    public function isRevoked(): bool
    {
        return $this->revoked_at !== null;
    }
}
