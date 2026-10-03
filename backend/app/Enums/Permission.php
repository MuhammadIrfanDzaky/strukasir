<?php

namespace App\Enums;

enum Permission: string
{
    case OrderCreate = 'order.create';
    case OrderVoid = 'order.void';
    case ShiftOperate = 'shift.operate';
    case DiscountWithinLimit = 'discount.within_limit';
    case DiscountOverLimit = 'discount.over_limit';
    case MenuManage = 'menu.manage';
    case UsersManage = 'users.manage';
    case SettingsManage = 'settings.manage';
    case ReportsView = 'reports.view';
    case DevicesManage = 'devices.manage';

    /** Fitur paket yang wajib aktif agar izin ini berlaku (dimensi entitlement tenant). */
    public function requiredFeature(): ?string
    {
        return match ($this) {
            self::DiscountWithinLimit, self::DiscountOverLimit => Feature::Discounts->value,
            default => null,
        };
    }
}
