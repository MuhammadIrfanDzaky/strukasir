<?php

namespace App\Enums;

/**
 * Daftar fitur yang bisa dinyalakan/dimatikan per paket dan per tenant.
 * Menambah fitur baru = tambah case di sini + baris di tabel `features` (FeatureSeeder).
 */
enum Feature: string
{
    case OpenBill = 'open_bill';
    case Modifiers = 'modifiers';
    case Discounts = 'discounts';
    case TaxService = 'tax_service';
    case SplitPayment = 'split_payment';
    case Reports = 'reports';

    public function description(): string
    {
        return match ($this) {
            self::OpenBill => 'Simpan order dan bayar nanti (struk belum bayar)',
            self::Modifiers => 'Varian & modifier produk (hot/cold, gula, extra shot)',
            self::Discounts => 'Diskon manual per item / per order',
            self::TaxService => 'Pajak dan service charge',
            self::SplitPayment => 'Satu order dibayar dengan beberapa metode',
            self::Reports => 'Laporan penjualan untuk owner',
        };
    }
}
