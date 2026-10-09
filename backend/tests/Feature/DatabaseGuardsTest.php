<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/** Aturan uang yang ditegakkan database, bukan hanya kode aplikasi (#19, #20, #32). */
class DatabaseGuardsTest extends TestCase
{
    private object $shop;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop();
    }

    private function inShop(callable $fn): mixed
    {
        return $this->tenancy()->run($this->shop->tenant->id, $fn);
    }

    private function insertOrder(string $status = 'open'): string
    {
        $id = (string) Str::uuid();
        DB::table('orders')->insert([
            'id' => $id,
            'tenant_id' => $this->shop->tenant->id,
            'device_id' => $this->shop->device->id,
            'outlet_id' => $this->shop->device->outlet_id,
            'cashier_id' => $this->shop->cashier->id,
            'business_date' => '2026-10-03',
            'number' => 'T1-'.random_int(1, 9999),
            'status' => $status,
            'grand_total' => 28000,
        ]);

        return $id;
    }

    private function insertPayment(string $orderId): string
    {
        $id = (string) Str::uuid();
        DB::table('payments')->insert([
            'id' => $id,
            'tenant_id' => $this->shop->tenant->id,
            'order_id' => $orderId,
            'method' => 'cash',
            'amount' => 28000,
            'tendered' => 30000,
            'change' => 2000,
            'confirmed_by' => $this->shop->cashier->id,
            'confirmed_at' => now(),
        ]);

        return $id;
    }

    public function test_payments_cannot_be_updated(): void
    {
        $this->expectException(QueryException::class);

        $this->inShop(function () {
            $paymentId = $this->insertPayment($this->insertOrder());
            DB::table('payments')->where('id', $paymentId)->update(['amount' => 1]);
        });
    }

    public function test_payments_cannot_be_deleted(): void
    {
        $this->expectException(QueryException::class);

        $this->inShop(function () {
            $paymentId = $this->insertPayment($this->insertOrder());
            DB::table('payments')->where('id', $paymentId)->delete();
        });
    }

    public function test_audit_logs_cannot_be_altered(): void
    {
        $this->expectException(QueryException::class);

        $this->inShop(function () {
            $log = AuditLog::create(['action' => 'test']);
            DB::table('audit_logs')->where('id', $log->id)->update(['action' => 'diubah']);
        });
    }

    public function test_paid_order_cannot_go_back_to_open(): void
    {
        $this->expectException(QueryException::class);

        $this->inShop(function () {
            $id = $this->insertOrder('paid');
            DB::table('orders')->where('id', $id)->update(['status' => 'open']);
        });
    }

    public function test_void_requires_reason_and_actor(): void
    {
        $this->expectException(QueryException::class);

        $this->inShop(function () {
            $id = $this->insertOrder('paid');
            DB::table('orders')->where('id', $id)->update(['status' => 'void']);
        });
    }

    public function test_paid_order_can_be_voided_with_reason(): void
    {
        $status = $this->inShop(function () {
            $id = $this->insertOrder('paid');
            DB::table('orders')->where('id', $id)->update([
                'status' => 'void', 'void_reason' => 'Salah input', 'voided_by' => $this->shop->owner->id,
            ]);

            return DB::table('orders')->where('id', $id)->value('status');
        });

        $this->assertSame('void', $status);
    }

    public function test_paid_order_totals_are_frozen(): void
    {
        $this->expectException(QueryException::class);

        $this->inShop(function () {
            $id = $this->insertOrder('paid');
            DB::table('orders')->where('id', $id)->update(['grand_total' => 1000]);
        });
    }

    public function test_only_one_open_shift_per_device(): void
    {
        $this->expectException(QueryException::class);

        $this->inShop(function () {
            foreach (range(1, 2) as $_) {
                DB::table('shifts')->insert([
                    'id' => (string) Str::uuid(),
                    'tenant_id' => $this->shop->tenant->id,
                    'device_id' => $this->shop->device->id,
                    'opened_by' => $this->shop->cashier->id,
                    'opened_at' => now(),
                    'opening_cash' => 100000,
                ]);
            }
        });
    }

    public function test_order_cannot_reference_cashier_of_another_tenant(): void
    {
        $other = $this->makeShop('Kedai Lain');

        $this->expectException(QueryException::class);

        $this->inShop(fn () => DB::table('orders')->insert([
            'id' => (string) Str::uuid(),
            'tenant_id' => $this->shop->tenant->id,
            'device_id' => $this->shop->device->id,
            'cashier_id' => $other->cashier->id,
            'business_date' => '2026-10-03',
            'number' => 'T1-1',
        ]));
    }
}
