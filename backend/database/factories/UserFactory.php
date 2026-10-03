<?php

namespace Database\Factories;

use App\Enums\Role;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Hash;

/**
 * Buat di dalam konteks tenant: app(TenantContext::class)->run($tenantId, fn () => User::factory()->create()).
 *
 * @extends Factory<User>
 */
class UserFactory extends Factory
{
    protected static ?string $pinHash = null;

    public function definition(): array
    {
        return [
            'name' => fake()->unique()->firstName(),
            'email' => null,
            'password' => null,
            'pin_hash' => static::$pinHash ??= Hash::make('123456'),
            'role' => Role::Cashier,
            'active' => true,
        ];
    }

    public function owner(string $password = 'owner-password-123'): static
    {
        return $this->state(fn () => [
            'role' => Role::Owner,
            'email' => fake()->unique()->safeEmail(),
            'password' => $password,
        ]);
    }

    public function pin(string $pin): static
    {
        return $this->state(fn () => ['pin_hash' => Hash::make($pin)]);
    }
}
