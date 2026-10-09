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
    // Kasir: cari, tautkan & daftarkan pelanggan. Owner: ubah, hapus data (anonim), import, statistik.
    case CustomersView = 'customers.view';
    case CustomersManage = 'customers.manage';
    // Kasbon melewati batas pelanggan (kasir butuh PIN owner).
    case CreditOverLimit = 'credit.over_limit';
    // Bahan, resep, pembelian, terbuang, stok opname.
    case InventoryManage = 'inventory.manage';

    /** Fitur paket yang wajib aktif agar izin ini berlaku (dimensi entitlement tenant). */
    public function requiredFeature(): ?string
    {
        return match ($this) {
            self::DiscountWithinLimit, self::DiscountOverLimit => Feature::Discounts->value,
            self::ReportsView => Feature::Reports->value,
            self::CustomersView, self::CustomersManage => Feature::Customers->value,
            self::CreditOverLimit => Feature::CustomerCredit->value,
            self::InventoryManage => Feature::Inventory->value,
            default => null,
        };
    }
}
