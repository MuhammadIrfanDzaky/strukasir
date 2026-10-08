<?php

namespace Tests\Feature;

use App\Enums\Feature;
use App\Models\AuditLog;
use App\Models\Category;
use App\Models\Payment;
use App\Models\Product;
use App\Services\ReportService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class ShiftVoidReportTest extends TestCase
{
    private object $shop;

    private string $cashier;

    private string $owner;

    private Product $latte;

    private Product $tea;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->cashier = $this->pinLogin($this->shop);
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);

        $this->tenancy()->run($this->shop->tenant->id, function () {
            $c = Category::create(['name' => 'Minuman']);
            $this->latte = Product::create(['category_id' => $c->id, 'name' => 'Latte', 'price' => 20000]);
            $this->tea = Product::create(['category_id' => $c->id, 'name' => 'Teh', 'price' => 10000]);
        });
    }

    private function openShift(int $cash = 100000): void
    {
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => $cash])->assertCreated();
    }

    /** Buat & bayar order; kembalikan ID-nya. */
    private function sell(Product $p, int $qty, string $method = 'cash', ?int $tendered = null): string
    {
        $id = (string) Str::uuid();
        $total = $p->price * $qty;
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $p->id, 'qty' => $qty, 'modifier_ids' => []]],
            'expected_total' => $total,
        ])->assertOk();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'expected_total' => $total,
            'payments' => [['id' => (string) Str::uuid(), 'method' => $method, 'amount' => $total,
                'tendered' => $method === 'cash' ? ($tendered ?? $total) : null]],
        ])->assertOk();

        return $id;
    }

    // ─────────────── shift ───────────────

    public function test_only_one_open_shift_per_tablet(): void
    {
        $this->openShift();
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 0])->assertStatus(409);
        $this->api('GET', '/api/v1/shifts/current', $this->cashier)->assertOk()->assertJsonPath('data.opening_cash', 100000);
    }

    public function test_close_shift_computes_expected_cash_and_difference(): void
    {
        $this->openShift(100000);
        $this->sell($this->latte, 1, 'cash', 50000);   // kas +20.000 (kembalian tidak dihitung)
        $this->sell($this->tea, 2, 'qris');             // bukan kas

        $closed = $this->api('POST', '/api/v1/shifts/close', $this->cashier, ['counted_cash' => 118000, 'note' => 'kurang 2rb'])
            ->assertOk()
            ->assertJsonPath('data.expected_cash', 120000)
            ->assertJsonPath('data.difference', -2000)
            ->assertJsonPath('data.summary.by_method.cash', 20000)
            ->assertJsonPath('data.summary.by_method.qris', 20000)
            ->assertJsonPath('data.summary.paid_orders', 2);

        $this->assertNotNull($closed->json('data.closed_at'));
        $this->api('GET', '/api/v1/shifts/current', $this->cashier)->assertOk()->assertJsonPath('data', null);
    }

    public function test_shift_history_is_owner_only(): void
    {
        $this->openShift();
        $this->api('GET', '/api/v1/shifts', $this->cashier)->assertForbidden();
        $this->api('GET', '/api/v1/shifts', $this->owner)->assertOk()->assertJsonCount(1, 'data');
    }

    // ─────────────── void / refund ───────────────

    public function test_cashier_void_needs_owner_pin_and_reason(): void
    {
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->tea->id, 'qty' => 1, 'modifier_ids' => []]],
            'expected_total' => 10000,
        ])->assertOk();

        $this->api('POST', "/api/v1/orders/{$id}/void", $this->cashier, [])->assertUnprocessable()->assertJsonValidationErrors('reason');
        $this->api('POST', "/api/v1/orders/{$id}/void", $this->cashier, ['reason' => 'Pelanggan batal'])
            ->assertUnprocessable()->assertJsonValidationErrors('approval');

        $this->api('POST', "/api/v1/orders/{$id}/void", $this->cashier, [
            'reason' => 'Pelanggan batal',
            'approval' => ['user_id' => $this->shop->owner->id, 'pin' => self::PIN],
        ])->assertOk()->assertJsonPath('data.status', 'void');

        $log = $this->tenancy()->run($this->shop->tenant->id, fn () => AuditLog::where('action', 'order.voided')->first());
        $this->assertSame($this->shop->owner->id, $log->after['approver_id']);
        $this->assertSame('Pelanggan batal', $log->after['reason']);
    }

    public function test_voiding_paid_order_refunds_into_current_shift(): void
    {
        $this->openShift(100000);
        $id = $this->sell($this->latte, 2); // 40.000 tunai

        $this->api('POST', "/api/v1/orders/{$id}/void", $this->owner, ['reason' => 'Salah input'])
            ->assertOk()->assertJsonPath('data.status', 'void');
        // Kiriman ulang aman: tidak membuat refund kedua.
        $this->api('POST', "/api/v1/orders/{$id}/void", $this->owner, ['reason' => 'Salah input'])->assertOk();

        $refunds = $this->tenancy()->run($this->shop->tenant->id, fn () => Payment::where('kind', 'refund')->get());
        $this->assertCount(1, $refunds);
        $this->assertSame(40000, $refunds->first()->amount);

        $this->api('POST', '/api/v1/shifts/close', $this->cashier, ['counted_cash' => 100000])
            ->assertOk()
            ->assertJsonPath('data.expected_cash', 100000) // 100.000 + 40.000 − 40.000
            ->assertJsonPath('data.difference', 0)
            ->assertJsonPath('data.summary.cash_refund', 40000);
    }

    public function test_cannot_void_another_tenants_order(): void
    {
        $this->openShift();
        $id = $this->sell($this->tea, 1);
        $other = $this->makeShop('Kedai Lain');

        $this->api('POST', "/api/v1/orders/{$id}/void", $this->pinLogin($other, $other->owner), ['reason' => 'Iseng'])
            ->assertNotFound();
    }

    // ─────────────── laporan ───────────────

    public function test_gross_profit_uses_cost_at_time_of_sale(): void
    {
        $this->tenancy()->run($this->shop->tenant->id, fn () => $this->latte->update(['cost' => 8000]));
        $this->openShift();
        $this->sell($this->latte, 2);   // 40.000, HPP 16.000
        $this->sell($this->tea, 1);     // 10.000, modal belum diisi
        // Modal diubah setelah transaksi → laporan tetap memakai modal saat transaksi.
        $this->tenancy()->run($this->shop->tenant->id, fn () => $this->latte->update(['cost' => 15000]));

        $today = now()->setTimezone('Asia/Jakarta')->toDateString();
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)
            ->assertOk()
            ->assertJsonPath('data.sales', 50000)
            ->assertJsonPath('data.cost', 16000)
            ->assertJsonPath('data.gross_profit', 34000)
            ->assertJsonPath('data.cost_missing_items', 1)
            ->assertJsonPath('data.top_products.0.name', 'Latte')
            ->assertJsonPath('data.top_products.0.profit', 24000)
            ->assertJsonPath('data.top_products.1.profit', null);
    }

    public function test_sales_report_counts_paid_orders_only(): void
    {
        $this->openShift();
        $this->sell($this->latte, 2);            // 40.000 tunai
        $this->sell($this->tea, 3, 'qris');      // 30.000 QRIS
        $voided = $this->sell($this->tea, 1);    // 10.000 → di-void
        $this->api('POST', "/api/v1/orders/{$voided}/void", $this->owner, ['reason' => 'Batal'])->assertOk();

        $today = now()->setTimezone('Asia/Jakarta')->toDateString();
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)
            ->assertOk()
            ->assertJsonPath('data.orders', 2)
            ->assertJsonPath('data.sales', 70000)
            ->assertJsonPath('data.average', 35000)
            ->assertJsonPath('data.by_method.cash', 40000)
            ->assertJsonPath('data.by_method.qris', 30000)
            ->assertJsonPath('data.voids.orders', 1)
            ->assertJsonPath('data.voids.refunded', 10000)
            ->assertJsonPath('data.top_products.0.name', 'Teh')
            ->assertJsonPath('data.top_products.0.qty', 3)
            ->assertJsonPath('data.by_cashier.0.name', 'Kasir');
    }

    public function test_dashboard_breakdowns_by_hour_weekday_category_and_previous_period(): void
    {
        $this->travelTo(now()->setTimezone('Asia/Jakarta')->setTime(10, 15)->utc());
        $this->openShift();
        $this->sell($this->latte, 2);        // 40.000 jam 10 WIB
        $this->sell($this->tea, 1);          // 10.000

        $today = now()->setTimezone('Asia/Jakarta');
        $date = $today->toDateString();
        $res = $this->api('GET', "/api/v1/reports/summary?from={$date}&to={$date}", $this->owner)->assertOk();

        $hourly = collect($res->json('data.hourly'));
        $this->assertCount(24, $hourly);
        $this->assertSame(['orders' => 2, 'sales' => 50000], collect($hourly->firstWhere('hour', 10))->only(['orders', 'sales'])->all(),
            'jam memakai zona waktu kedai, bukan UTC');
        $this->assertSame(50000, $hourly->sum('sales'));

        $weekday = collect($res->json('data.weekday'));
        $this->assertCount(7, $weekday);
        $this->assertSame(50000, $weekday->firstWhere('day', $today->isoWeekday())['sales']);

        $res->assertJsonPath('data.by_category.0.name', 'Minuman')->assertJsonPath('data.by_category.0.revenue', 50000);

        // Periode sebelumnya = hari kemarin (panjang sama), belum ada penjualan.
        $res->assertJsonPath('data.previous.to', $today->copy()->subDay()->toDateString())
            ->assertJsonPath('data.previous.sales', 0);
    }

    public function test_previous_period_has_same_length(): void
    {
        $this->assertSame(['2026-09-24', '2026-09-30'], ReportService::previousRange('2026-10-01', '2026-10-07'));
        $this->assertSame(['2026-09-30', '2026-09-30'], ReportService::previousRange('2026-10-01', '2026-10-01'));
    }

    public function test_report_is_owner_only_and_follows_feature(): void
    {
        $today = now()->toDateString();
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->cashier)->assertForbidden();

        $this->tenancy()->run($this->shop->tenant->id, fn () => DB::table('tenant_features')->insert([
            'tenant_id' => $this->shop->tenant->id, 'feature_key' => Feature::Reports->value, 'enabled' => false,
        ]));
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)->assertForbidden();
    }
}
