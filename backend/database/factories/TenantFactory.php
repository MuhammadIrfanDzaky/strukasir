<?php

namespace Database\Factories;

use App\Models\Plan;
use App\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Tenant> */
class TenantFactory extends Factory
{
    public function definition(): array
    {
        return [
            'code' => fake()->unique()->slug(2),
            'name' => fake()->company(),
            'plan_id' => Plan::factory(),
            'timezone' => 'Asia/Jakarta',
            'status' => 'active',
        ];
    }
}
