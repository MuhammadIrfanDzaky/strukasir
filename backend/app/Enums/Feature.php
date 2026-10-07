<?php

namespace App\Enums;

/**
 * Daftar fitur yang bisa dinyalakan/dimatikan per paket dan per tenant.
 * Menambah fitur baru = tambah case di sini + baris di tabel `features` (FeatureSeeder).
 */
enum Feature: string
{
    case CustomerName = 'customer_name';
    case OpenBill = 'open_bill';
    case Modifiers = 'modifiers';
    case Discounts = 'discounts';
    case TaxService = 'tax_service';
    case SplitPayment = 'split_payment';
    case Reports = 'reports';

    public function description(): string
    {
        return match ($this) {
            self::CustomerName => 'Nama pelanggan / nomor meja wajib diisi di setiap order',
            self::OpenBill => 'Simpan order dan bayar nanti (struk belum bayar)',
            self::Modifiers => 'Varian & modifier produk (hot/cold, gula, extra shot)',
            self::Discounts => 'Diskon manual per item / per order',
            self::TaxService => 'Pajak dan service charge',
            self::SplitPayment => 'Satu order dibayar dengan beberapa metode',
            self::Reports => 'Laporan penjualan untuk owner',
        };
    }

    /** Nama singkat di layar Pengaturan → Fitur. */
    public function label(): string
    {
        return match ($this) {
            self::CustomerName => 'Nama pelanggan / meja',
            self::OpenBill => 'Open Bill (bayar nanti)',
            self::Modifiers => 'Varian produk',
            self::Discounts => 'Diskon',
            self::TaxService => 'Pajak & service',
            self::SplitPayment => 'Bayar dengan beberapa metode',
            self::Reports => 'Laporan',
        };
    }

    /** Fitur yang boleh dinyalakan/dimatikan owner sendiri (sisanya diatur paket). */
    public function ownerToggleable(): bool
    {
        return $this !== self::Reports;
    }

    /** Fitur lain yang harus aktif agar fitur ini bisa aktif. */
    public function requires(): ?self
    {
        return match ($this) {
            // Order yang disimpan harus bisa dikenali saat dibuka lagi.
            self::OpenBill => self::CustomerName,
            default => null,
        };
    }
}
