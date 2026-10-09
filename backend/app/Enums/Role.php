<?php

namespace App\Enums;

/**
 * Role di dalam satu tenant. Izin didefinisikan eksplisit per role (bukan boolean is_admin),
 * lalu didaftarkan sebagai Gate di AppServiceProvider.
 */
enum Role: string
{
    case Owner = 'owner';
    case Cashier = 'cashier';

    /** @return list<Permission> */
    public function permissions(): array
    {
        return match ($this) {
            self::Owner => Permission::cases(),
            self::Cashier => [
                Permission::OrderCreate,
                Permission::ShiftOperate,
                Permission::DiscountWithinLimit,
                Permission::CustomersView,
            ],
        };
    }

    public function allows(Permission $permission): bool
    {
        return in_array($permission, $this->permissions(), true);
    }
}
