<?php

namespace App\Models;

use App\Enums\Role;
use App\Models\Concerns\BelongsToTenant;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use BelongsToTenant, HasApiTokens, HasFactory, HasUuids;

    public const MAX_FAILED_ATTEMPTS = 5;

    public const LOCKOUT_MINUTES = 5;

    // tenant_id, role, failed_attempts, locked_until sengaja TIDAK fillable (SEC-03).
    protected $fillable = ['name', 'email'];

    protected $hidden = ['password', 'pin_hash', 'remember_token'];

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'role' => Role::class,
            'active' => 'boolean',
            'locked_until' => 'datetime',
        ];
    }

    /** Model identitas: boleh dibaca saat resolusi token, sebelum tenant diketahui. */
    public function requiresTenantContext(): bool
    {
        return false;
    }

    public function setPin(string $pin): void
    {
        $this->pin_hash = Hash::make($pin);
    }

    public function isLocked(): bool
    {
        return $this->locked_until !== null && $this->locked_until->isFuture();
    }

    /** Catat percobaan gagal; kunci akun setelah MAX_FAILED_ATTEMPTS berturut-turut. */
    public function registerFailedAttempt(): void
    {
        $this->failed_attempts++;

        if ($this->failed_attempts >= self::MAX_FAILED_ATTEMPTS) {
            $this->locked_until = now()->addMinutes(self::LOCKOUT_MINUTES);
            $this->failed_attempts = 0;
        }

        $this->save();
    }

    public function clearFailedAttempts(): void
    {
        if ($this->failed_attempts !== 0 || $this->locked_until !== null) {
            $this->failed_attempts = 0;
            $this->locked_until = null;
            $this->save();
        }
    }
}
