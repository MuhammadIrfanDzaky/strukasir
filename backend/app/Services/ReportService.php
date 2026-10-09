<?php

namespace App\Services;

use App\Models\Tenant;
use App\Support\Tenancy\TenantContext;
use Carbon\CarbonImmutable;
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

        $paidItems = fn () => DB::table('order_items')
            ->join('orders', 'orders.id', '=', 'order_items.order_id')
            ->where('orders.status', 'paid')->whereBetween('orders.business_date', [$from, $to]);

        $topProducts = $paidItems()
            ->groupBy('order_items.name')
            ->selectRaw('order_items.name, sum(order_items.qty) as qty, sum(order_items.line_total) as revenue,
                coalesce(sum(order_items.unit_cost * order_items.qty),0) as cost,
                count(*) filter (where order_items.unit_cost is null) as missing_cost')
            ->orderByDesc('qty')->limit(10)->get();

        // HPP dari salinan modal saat transaksi (order_items.unit_cost); item tanpa modal dihitung terpisah.
        $costs = $paidItems()->selectRaw('coalesce(sum(order_items.unit_cost * order_items.qty),0) as cost,
            count(*) filter (where order_items.unit_cost is null) as missing')->first();

        $byCashier = $paid()
            ->join('users', 'users.id', '=', 'orders.cashier_id')
            ->groupBy('users.name')
            ->selectRaw('users.name, count(*) as orders, sum(orders.grand_total) as sales')
            ->orderByDesc('sales')->get();

        $daily = $paid()->groupBy('business_date')->orderBy('business_date')
            ->selectRaw('business_date, count(*) as orders, sum(grand_total) as sales')->get();

        // Jam & hari dihitung dari waktu bayar di zona waktu kedai (paid_at disimpan UTC).
        $tz = Tenant::query()->whereKey(app(TenantContext::class)->id())->value('timezone') ?: 'Asia/Jakarta';
        $local = "((orders.paid_at at time zone 'UTC') at time zone ?)";
        $hourly = $paid()->selectRaw("extract(hour from {$local})::int as h, count(*) as orders, sum(grand_total) as sales", [$tz])
            ->groupByRaw('1')->get()->keyBy('h');
        // ISO: 1 = Senin … 7 = Minggu.
        $weekday = $paid()->selectRaw("extract(isodow from {$local})::int as d, count(*) as orders, sum(grand_total) as sales", [$tz])
            ->groupByRaw('1')->get()->keyBy('d');

        // Omzet per kategori produk (nilai baris setelah diskon item); produk terhapus → "Lainnya".
        $byCategory = $paidItems()
            ->leftJoin('products', 'products.id', '=', 'order_items.product_id')
            ->leftJoin('categories', 'categories.id', '=', 'products.category_id')
            ->groupBy('categories.name')
            ->selectRaw("coalesce(categories.name, 'Lainnya') as name, sum(order_items.qty) as qty, sum(order_items.line_total) as revenue")
            ->orderByDesc('revenue')->get();

        // Pelanggan / member: porsi transaksi member, pelanggan baru vs kembali, pelanggan teratas.
        $members = $paid()->whereNotNull('customer_id')
            ->selectRaw('count(*) as orders, coalesce(sum(grand_total),0) as sales, count(distinct customer_id) as customers')->first();
        // "Baru" = transaksi lunas pertamanya jatuh di periode ini.
        $newCustomers = DB::table('orders')->where('status', 'paid')->whereNotNull('customer_id')
            ->groupBy('customer_id')->havingRaw('min(business_date) between ? and ?', [$from, $to])
            ->select('customer_id')->get()->count();
        $topCustomers = $paid()->join('customers', 'customers.id', '=', 'orders.customer_id')
            ->groupBy('customers.id', 'customers.code', 'customers.name')
            ->selectRaw('customers.id, customers.code, customers.name, count(*) as orders, sum(orders.grand_total) as sales')
            ->orderByDesc('sales')->limit(5)->get();

        // Loyalitas: stempel/poin keluar & ditukar (dari order lunas di periode ini), hadiah terpopuler.
        $loyaltyUnits = DB::table('loyalty_entries')->join('orders', 'orders.id', '=', 'loyalty_entries.order_id')
            ->where('orders.status', 'paid')->whereBetween('orders.business_date', [$from, $to])
            ->selectRaw("coalesce(sum(units) filter (where kind = 'earn'), 0) as earned, coalesce(-sum(units) filter (where kind = 'redeem'), 0) as redeemed")
            ->first();
        $rewards = $paid()->whereNotNull('reward_id')->groupBy('reward_name')
            ->selectRaw('reward_name as name, count(*) as count, sum(reward_discount) as discount')
            ->orderByDesc('count')->limit(5)->get();

        // Penjualan per tingkat member (salinan tingkat di order).
        $byTier = $paid()->whereNotNull('tier_name')->groupBy('tier_name')
            ->selectRaw('tier_name as name, count(*) as orders, sum(grand_total) as sales, count(distinct customer_id) as customers, sum(tier_discount) as discount')
            ->orderByDesc('sales')->get();

        // Kasbon: pelunasan di periode (hari lokal kedai) & piutang yang masih terbuka sekarang.
        $repaid = (int) DB::table('credit_repayments')
            ->whereRaw("((created_at at time zone 'UTC') at time zone ?)::date between ? and ?", [$tz, $from, $to])
            ->sum(DB::raw("case when kind = 'repayment' then amount else -amount end"));
        $debtors = DB::query()->fromSub(CreditService::balanceQuery(), 'b')
            ->join('customers', 'customers.id', '=', 'b.customer_id')
            ->where('b.credit_balance', '>', 0)
            ->orderByDesc('b.credit_balance')
            ->get(['customers.id', 'customers.code', 'customers.name', 'b.credit_balance']);

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
            // Laba kotor = penjualan − pajak (bukan milik kedai) − HPP. Akurat bila cost_missing_items = 0.
            'cost' => (int) $costs->cost,
            'gross_profit' => $sales - (int) $totals->tax - (int) $costs->cost,
            'cost_missing_items' => (int) $costs->missing,
            'voids' => ['orders' => (int) $voids->orders, 'refunded' => (int) $voids->refunded],
            'by_method' => collect(['cash', 'debit', 'qris', 'credit'])->mapWithKeys(fn ($m) => [
                $m => (int) ($byMethod->firstWhere('method', $m)->total ?? 0),
            ]),
            'top_products' => $topProducts->map(fn ($r) => [
                'name' => $r->name, 'qty' => (int) $r->qty, 'revenue' => (int) $r->revenue,
                // Laba per produk (sebelum diskon order & pajak); null bila ada item tanpa modal.
                'profit' => (int) $r->missing_cost === 0 ? (int) $r->revenue - (int) $r->cost : null,
            ]),
            'by_cashier' => $byCashier->map(fn ($r) => [
                'name' => $r->name, 'orders' => (int) $r->orders, 'sales' => (int) $r->sales,
            ]),
            'daily' => $daily->map(fn ($r) => [
                'date' => (string) $r->business_date, 'orders' => (int) $r->orders, 'sales' => (int) $r->sales,
            ]),
            // Lengkap 24 jam / 7 hari (nol bila sepi) supaya grafik tidak perlu mengisi celah.
            'hourly' => collect(range(0, 23))->map(fn (int $h) => [
                'hour' => $h, 'orders' => (int) ($hourly[$h]->orders ?? 0), 'sales' => (int) ($hourly[$h]->sales ?? 0),
            ]),
            'weekday' => collect(range(1, 7))->map(fn (int $d) => [
                'day' => $d, 'orders' => (int) ($weekday[$d]->orders ?? 0), 'sales' => (int) ($weekday[$d]->sales ?? 0),
            ]),
            'by_category' => $byCategory->map(fn ($r) => [
                'name' => $r->name, 'qty' => (int) $r->qty, 'revenue' => (int) $r->revenue,
            ]),
            'customers' => [
                'orders' => (int) $members->orders,
                'sales' => (int) $members->sales,
                'active' => (int) $members->customers,
                'new' => $newCustomers,
                'returning' => max(0, (int) $members->customers - $newCustomers),
                'top' => $topCustomers->map(fn ($r) => [
                    'id' => $r->id, 'code' => $r->code, 'name' => $r->name, 'orders' => (int) $r->orders, 'sales' => (int) $r->sales,
                ]),
            ],
            'credit' => [
                'issued' => (int) ($byMethod->firstWhere('method', 'credit')->total ?? 0),
                'repaid' => $repaid,
                'outstanding' => (int) $debtors->sum('credit_balance'),
                'debtors' => $debtors->count(),
                'top' => $debtors->take(5)->map(fn ($d) => [
                    'id' => $d->id, 'code' => $d->code, 'name' => $d->name, 'balance' => (int) $d->credit_balance,
                ])->values(),
            ],
            'by_tier' => $byTier->map(fn ($r) => [
                'name' => $r->name, 'orders' => (int) $r->orders, 'sales' => (int) $r->sales,
                'customers' => (int) $r->customers, 'discount' => (int) $r->discount,
            ]),
            'loyalty' => [
                'earned' => (int) $loyaltyUnits->earned,
                'redeemed' => (int) $loyaltyUnits->redeemed,
                'rewards' => $rewards->map(fn ($r) => ['name' => $r->name, 'count' => (int) $r->count, 'discount' => (int) $r->discount]),
            ],
            // Periode sebelumnya dengan panjang sama (mis. 7 hari sebelumnya) untuk naik/turun di dashboard.
            'previous' => $this->totals(...self::previousRange($from, $to)),
        ];
    }

    /** @return array{0: string, 1: string} */
    public static function previousRange(string $from, string $to): array
    {
        $start = CarbonImmutable::parse($from);
        $days = $start->diffInDays(CarbonImmutable::parse($to)) + 1;

        return [$start->subDays($days)->toDateString(), $start->subDay()->toDateString()];
    }

    /** Angka ringkas untuk perbandingan: transaksi, penjualan, rata-rata, laba kotor. */
    private function totals(string $from, string $to): array
    {
        $t = DB::table('orders')->where('status', 'paid')->whereBetween('business_date', [$from, $to])
            ->selectRaw('count(*) as orders, coalesce(sum(grand_total),0) as sales, coalesce(sum(tax_total),0) as tax')->first();
        $cost = (int) DB::table('order_items')->join('orders', 'orders.id', '=', 'order_items.order_id')
            ->where('orders.status', 'paid')->whereBetween('orders.business_date', [$from, $to])
            ->sum(DB::raw('coalesce(order_items.unit_cost * order_items.qty, 0)'));
        $orders = (int) $t->orders;
        $sales = (int) $t->sales;

        return [
            'from' => $from, 'to' => $to, 'orders' => $orders, 'sales' => $sales,
            'average' => $orders > 0 ? intdiv($sales, $orders) : 0,
            'gross_profit' => $sales - (int) $t->tax - $cost,
        ];
    }
}
