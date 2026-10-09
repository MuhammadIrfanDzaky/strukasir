<?php

namespace App\Services;

use App\Models\Tenant;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Ekspor laporan ke CSV untuk Excel / Google Sheets. Pemisah titik-koma + BOM UTF-8 supaya langsung
 * rapi dibuka Excel berbahasa Indonesia; angka rupiah tanpa titik ribuan agar bisa dijumlah.
 * Semua query ter-scope tenant oleh RLS (dijalankan di dalam TenantContext::run).
 */
class ReportExportService
{
    public const TYPES = [
        'orders' => 'Penjualan per transaksi',
        'items' => 'Penjualan per item',
        'tax' => 'Rekap pajak (PB1) per hari',
        'cash' => 'Kas keluar / masuk',
    ];

    /** @return array{0: list<string>, 1: iterable<list<scalar|null>>} judul kolom & baris */
    /** @param  string|null  $outletId  null = semua outlet (kolom Outlet membedakan baris) */
    public function rows(string $type, string $from, string $to, ?string $outletId = null): array
    {
        $o = fn ($q, string $column = 'orders.outlet_id') => $outletId === null ? $q : $q->where($column, $outletId);
        $tz = Tenant::query()->whereKey(app(TenantContext::class)->id())->value('timezone') ?: 'Asia/Jakarta';
        $local = fn (?string $ts) => $ts === null ? null : Carbon::parse($ts, 'UTC')->setTimezone($tz);

        return match ($type) {
            'orders' => [
                ['Tanggal', 'Jam', 'Outlet', 'No. order', 'Status', 'Kasir', 'Pelanggan', 'Kode member', 'Subtotal', 'Diskon', 'Service', 'Pajak',
                    'Pembulatan', 'Total', 'Tunai', 'Debit', 'QRIS', 'Kasbon'],
                $o(DB::table('orders'))
                    ->leftJoin('outlets', 'outlets.id', '=', 'orders.outlet_id')
                    ->leftJoin('users', 'users.id', '=', 'orders.cashier_id')
                    ->leftJoin('customers', 'customers.id', '=', 'orders.customer_id')
                    ->whereIn('orders.status', ['paid', 'void'])->whereBetween('orders.business_date', [$from, $to])
                    ->orderBy('orders.business_date')->orderBy('orders.paid_at')
                    ->select('orders.*', 'users.name as cashier_name', 'customers.code as customer_code', 'outlets.name as outlet_name')
                    ->selectRaw("(select coalesce(sum(case when kind='payment' then amount else 0 end),0) from payments p where p.order_id = orders.id and p.method='cash') as m_cash")
                    ->selectRaw("(select coalesce(sum(case when kind='payment' then amount else 0 end),0) from payments p where p.order_id = orders.id and p.method='debit') as m_debit")
                    ->selectRaw("(select coalesce(sum(case when kind='payment' then amount else 0 end),0) from payments p where p.order_id = orders.id and p.method='qris') as m_qris")
                    ->selectRaw("(select coalesce(sum(case when kind='payment' then amount else 0 end),0) from payments p where p.order_id = orders.id and p.method='credit') as m_credit")
                    ->lazy(500)
                    ->map(fn ($o) => [
                        $o->business_date,
                        $local($o->paid_at ?? $o->created_at)?->format('H:i'),
                        $o->outlet_name,
                        $o->number,
                        $o->status === 'paid' ? 'Lunas' : 'Void',
                        $o->cashier_name,
                        $o->customer_label,
                        $o->customer_code,
                        $o->subtotal, $o->discount_total, $o->service_total, $o->tax_total, $o->rounding, $o->grand_total,
                        $o->m_cash, $o->m_debit, $o->m_qris, $o->m_credit,
                    ]),
            ],
            'items' => [
                ['Tanggal', 'Outlet', 'No. order', 'Produk', 'Kategori', 'Pilihan', 'Qty', 'Harga satuan', 'Diskon', 'Total', 'Modal (HPP) total'],
                $o(DB::table('order_items')
                    ->join('orders', 'orders.id', '=', 'order_items.order_id'))
                    ->leftJoin('outlets', 'outlets.id', '=', 'orders.outlet_id')
                    ->leftJoin('products', 'products.id', '=', 'order_items.product_id')
                    ->leftJoin('categories', 'categories.id', '=', 'products.category_id')
                    ->where('orders.status', 'paid')->whereBetween('orders.business_date', [$from, $to])
                    ->orderBy('orders.business_date')->orderBy('orders.paid_at')->orderBy('order_items.sort')
                    ->select('order_items.*', 'orders.business_date', 'orders.number', 'categories.name as category_name', 'outlets.name as outlet_name')
                    ->selectRaw("(select string_agg(case when m.qty > 1 then m.name || ' x' || m.qty else m.name end, ', ') from order_item_modifiers m where m.order_item_id = order_items.id) as options")
                    ->lazy(500)
                    ->map(fn ($i) => [
                        $i->business_date, $i->outlet_name, $i->number, $i->name, $i->category_name ?? 'Lainnya', $i->options,
                        $i->qty, $i->unit_price + $i->modifiers_total, $i->discount_total, $i->line_total,
                        $i->unit_cost === null ? null : $i->unit_cost * $i->qty,
                    ]),
            ],
            // Rekap untuk lapor PB1 (per outlet: pajak daerah dilaporkan per lokasi usaha).
            // DPP = penjualan − pajak (harga sudah/ belum termasuk pajak sama-sama benar).
            'tax' => [
                ['Tanggal', 'Outlet', 'Jumlah transaksi', 'Penjualan (total dibayar)', 'Service', 'Pajak (PB1)', 'DPP (penjualan − pajak)'],
                $o(DB::table('orders'))->join('outlets', 'outlets.id', '=', 'orders.outlet_id')
                    ->where('orders.status', 'paid')->whereBetween('orders.business_date', [$from, $to])
                    ->groupBy('orders.business_date', 'outlets.code', 'outlets.name')->orderBy('orders.business_date')->orderByRaw('length(outlets.code), outlets.code')
                    ->selectRaw('orders.business_date, outlets.name as outlet_name, count(*) as n, sum(orders.grand_total) as sales, sum(orders.service_total) as service, sum(orders.tax_total) as tax')
                    ->get()
                    ->map(fn ($d) => [$d->business_date, $d->outlet_name, (int) $d->n, (int) $d->sales, (int) $d->service, (int) $d->tax, (int) $d->sales - (int) $d->tax]),
            ],
            default => [
                ['Tanggal', 'Jam', 'Outlet', 'Jenis', 'Kategori', 'Nominal', 'Keterangan', 'Dicatat oleh', 'Status'],
                $o(DB::table('cash_movements as m')->join('shifts', 'shifts.id', '=', 'm.shift_id'), 'shifts.outlet_id')
                    ->join('outlets', 'outlets.id', '=', 'shifts.outlet_id')
                    ->leftJoin('users', 'users.id', '=', 'm.created_by')
                    ->whereNull('m.reversal_of')
                    ->whereRaw("((m.created_at at time zone 'UTC') at time zone ?)::date between ? and ?", [$tz, $from, $to])
                    ->orderBy('m.created_at')
                    ->select('m.*', 'users.name as user_name', 'outlets.name as outlet_name')
                    ->selectRaw('exists(select 1 from cash_movements r where r.reversal_of = m.id) as cancelled')
                    ->get()
                    ->map(fn ($m) => [
                        $local($m->created_at)->toDateString(), $local($m->created_at)->format('H:i'), $m->outlet_name,
                        $m->kind === 'out' ? 'Keluar' : 'Masuk',
                        CashMovementService::CATEGORIES[$m->kind][$m->category][0] ?? $m->category,
                        (int) $m->amount, $m->note, $m->user_name, $m->cancelled ? 'Dibatalkan' : '',
                    ]),
            ],
        };
    }

    /** Tulis CSV (BOM + ';') ke output stream. */
    public function write(string $type, string $from, string $to, $out, ?string $outletId = null): void
    {
        [$header, $rows] = $this->rows($type, $from, $to, $outletId);
        fwrite($out, "\xEF\xBB\xBF");
        fputcsv($out, $header, ';', '"', '');
        foreach ($rows as $row) {
            fputcsv($out, array_map(fn ($v) => is_string($v) ? self::safe($v) : $v, $row), ';', '"', '');
        }
    }

    /** Cegah formula injection di Excel (teks yang diawali = + - @ dijadikan teks biasa). */
    private static function safe(string $v): string
    {
        return preg_match('/^[=+\-@\t\r]/', $v) ? "'".$v : $v;
    }
}
