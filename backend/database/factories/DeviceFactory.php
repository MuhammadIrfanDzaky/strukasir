<?php

namespace Database\Factories;

use App\Models\Device;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Device> */
class DeviceFactory extends Factory
{
    public function definition(): array
    {
        return [
            'code' => 'T'.fake()->unique()->numberBetween(1, 999),
            'name' => 'Tablet Kasir',
        ];
    }
}
