<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

/**
 * Laporan penjualan per rentang hari bisnis. Hanya order LUNAS yang dihitung sebagai penjualan;
 * order void dilaporkan terpisah. Semua query ter-scope tenant oleh RLS.
 */
class ReportService
{
    /** @return array<string, mixed> */
    public function summary(string $from, string $to): array
    {
        $paid = fn () => DB::table('orders')->where('status', 'paid')->whereBetween('business_date', [$from, $to]);

        $totals = $paid()->selectRaw('count(*) as orders, coalesce(sum(grand_total),0) as sales,
            coalesce(sum(discount_total),0) as discounts, coalesce(sum(service_total),0) as service,
            coalesce(sum(tax_total),0) as tax, coalesce(sum(rounding),0) as rounding')->first();

        $voids = DB::table('orders')->where('status', 'void')->whereBetween('business_date', [$from, $to])
            ->selectRaw('count(*) as orders, coalesce(sum(case when paid_at is not null then grand_total else 0 end),0) as refunded')
            ->first();

        $byMethod = DB::table('payments')
            ->join('orders', 'orders.id', '=', 'payments.order_id')
            ->where('orders.status', 'paid')->where('payments.kind', 'payment')
            ->whereBetween('orders.business_date', [$from, $to])
            ->groupBy('payments.method')
            ->selectRaw('payments.method, sum(payments.amount) as total, count(*) as count')
            ->get();

        $topProducts = DB::table('order_items')
            ->join('orders', 'orders.id', '=', 'order_items.order_id')
            ->where('orders.status', 'paid')->whereBetween('orders.business_date', [$from, $to])
            ->groupBy('order_items.name')
            ->selectRaw('order_items.name, sum(order_items.qty) as qty, sum(order_items.line_total) as revenue')
            ->orderByDesc('qty')->limit(10)->get();

        $byCashier = $paid()
            ->join('users', 'users.id', '=', 'orders.cashier_id')
            ->groupBy('users.name')
            ->selectRaw('users.name, count(*) as orders, sum(orders.grand_total) as sales')
            ->orderByDesc('sales')->get();

        $daily = $paid()->groupBy('business_date')->orderBy('business_date')
            ->selectRaw('business_date, count(*) as orders, sum(grand_total) as sales')->get();

        $orders = (int) $totals->orders;
        $sales = (int) $totals->sales;

        return [
            'from' => $from,
            'to' => $to,
            'orders' => $orders,
            'sales' => $sales,
            'average' => $orders > 0 ? intdiv($sales, $orders) : 0,
            'discounts' => (int) $totals->discounts,
            'service' => (int) $totals->service,
            'tax' => (int) $totals->tax,
            'rounding' => (int) $totals->rounding,
            'voids' => ['orders' => (int) $voids->orders, 'refunded' => (int) $voids->refunded],
            'by_method' => collect(['cash', 'debit', 'qris'])->mapWithKeys(fn ($m) => [
                $m => (int) ($byMethod->firstWhere('method', $m)->total ?? 0),
            ]),
            'top_products' => $topProducts->map(fn ($r) => [
                'name' => $r->name, 'qty' => (int) $r->qty, 'revenue' => (int) $r->revenue,
            ]),
            'by_cashier' => $byCashier->map(fn ($r) => [
                'name' => $r->name, 'orders' => (int) $r->orders, 'sales' => (int) $r->sales,
            ]),
            'daily' => $daily->map(fn ($r) => [
                'date' => (string) $r->business_date, 'orders' => (int) $r->orders, 'sales' => (int) $r->sales,
            ]),
        ];
    }
}
