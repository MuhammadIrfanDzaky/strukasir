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
    case Customers = 'customers';
    case Loyalty = 'loyalty';
    case MemberTiers = 'member_tiers';
    case CustomerCredit = 'customer_credit';

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
            self::Customers => 'Data pelanggan / member: cari & tautkan ke order, riwayat belanja, kelompok pelanggan',
            self::Loyalty => 'Program loyalitas: stempel / poin dari belanja member, tukar hadiah',
            self::MemberTiers => 'Tingkat member (mis. Silver/Gold): naik otomatis dari belanja, diskon & pengali stempel',
            self::CustomerCredit => 'Kasbon / piutang member: bayar nanti dengan batas, pelunasan di kasir, laporan piutang',
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
            self::Customers => 'Pelanggan / member',
            self::Loyalty => 'Program loyalitas',
            self::MemberTiers => 'Tingkat member',
            self::CustomerCredit => 'Kasbon (bayar nanti)',
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
            // Stempel / poin dicatat per member.
            self::Loyalty => self::Customers,
            self::MemberTiers => self::Customers,
            self::CustomerCredit => self::Customers,
            default => null,
        };
    }
}
