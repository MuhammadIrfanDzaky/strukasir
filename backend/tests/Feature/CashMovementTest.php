<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\Shift;
use App\Services\ShiftService;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class CashMovementTest extends TestCase
{
    private object $shop;

    private string $cashier;

    private string $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->cashier = $this->pinLogin($this->shop);
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 100000])->assertCreated();
    }

    private function move(string $kind, string $category, int $amount, array $extra = [])
    {
        return $this->api('POST', '/api/v1/shifts/current/cash-movements', $this->cashier, [
            'id' => (string) Str::uuid(), 'kind' => $kind, 'category' => $category, 'amount' => $amount, ...$extra,
        ]);
    }

    private function summary(): array
    {
        return $this->tenancy()->run($this->shop->tenant->id, fn () => app(ShiftService::class)
            ->summary(Shift::query()->whereNull('closed_at')->firstOrFail()));
    }

    public function test_cash_out_and_in_change_expected_cash(): void
    {
        $this->move('out', 'ingredients', 25000, ['note' => 'Es batu & susu'])->assertCreated();
        $this->move('in', 'float', 50000)->assertCreated();

        $s = $this->summary();
        $this->assertSame([25000, 50000, 125000], [$s['cash_out'], $s['cash_extra_in'], $s['expected_cash']]);

        $list = $this->api('GET', '/api/v1/shifts/current/cash-movements', $this->cashier)->assertOk();
        $list->assertJsonCount(2, 'data');
        $this->assertSame('Belanja bahan', collect($list->json('data'))->firstWhere('kind', 'out')['category_label']);
        $this->assertContains('withdrawal', array_column($list->json('categories'), 'key'));

        $close = $this->api('POST', '/api/v1/shifts/close', $this->cashier, ['counted_cash' => 125000])->assertOk();
        $close->assertJsonPath('data.difference', 0)->assertJsonPath('data.summary.cash_out', 25000);
    }

    public function test_validation_and_idempotency(): void
    {
        $this->move('out', 'float', 1000)->assertUnprocessable()->assertJsonValidationErrors('category');
        // Tidak boleh melebihi isi laci (tanpa menyebut angkanya).
        $res = $this->move('out', 'wages', 200000)->assertUnprocessable()->assertJsonValidationErrors('amount');
        $this->assertStringNotContainsString('100.000', $res->json('errors.amount.0'));

        $id = (string) Str::uuid();
        $this->move('out', 'operational', 10000, ['id' => $id])->assertCreated();
        $this->move('out', 'operational', 10000, ['id' => $id])->assertCreated();
        $this->assertSame(10000, $this->summary()['cash_out']);
        $this->move('out', 'operational', 999, ['id' => $id])->assertStatus(409);
    }

    public function test_cancel_needs_owner_pin_and_only_once(): void
    {
        $this->move('out', 'other_out', 15000)->assertCreated();
        $id = $this->api('GET', '/api/v1/shifts/current/cash-movements', $this->cashier)->json('data.0.id');
        $url = "/api/v1/cash-movements/{$id}/cancel";

        $this->api('POST', $url, $this->cashier, ['reason' => 'Salah ketik'])->assertUnprocessable()->assertJsonValidationErrors('approval');
        $this->api('POST', $url, $this->cashier, ['reason' => 'Salah ketik', 'approval' => ['user_id' => $this->shop->owner->id, 'pin' => self::PIN]])->assertOk();
        $this->api('POST', $url, $this->owner, ['reason' => 'Salah ketik'])->assertStatus(409);

        $this->assertSame([0, 100000], [$this->summary()['cash_out'], $this->summary()['expected_cash']]);
        $this->api('GET', '/api/v1/shifts/current/cash-movements', $this->cashier)->assertJsonCount(1, 'data')->assertJsonPath('data.0.cancelled', true);
    }

    public function test_needs_open_shift_and_is_append_only(): void
    {
        $this->move('out', 'ingredients', 1000)->assertCreated();
        $this->expectException(QueryException::class);
        $this->tenancy()->run($this->shop->tenant->id, fn () => DB::table('cash_movements')->update(['amount' => 1]));
    }

    public function test_no_shift_rejected(): void
    {
        $this->api('POST', '/api/v1/shifts/close', $this->cashier, ['counted_cash' => 100000])->assertOk();
        $this->move('in', 'float', 1000)->assertUnprocessable()->assertJsonValidationErrors('shift');
    }

    public function test_reports_show_expenses_and_net_profit(): void
    {
        $product = $this->tenancy()->run($this->shop->tenant->id, function () {
            $c = Category::create(['name' => 'Kopi']);

            return Product::create(['category_id' => $c->id, 'name' => 'Latte', 'price' => 50000, 'cost' => 20000]);
        });
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $product->id, 'qty' => 2, 'modifier_ids' => []]],
            'expected_total' => 100000,
        ])->assertOk();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => 100000, 'tendered' => 100000]],
            'expected_total' => 100000,
        ])->assertOk();
        $this->move('out', 'ingredients', 15000)->assertCreated();
        $this->move('out', 'wages', 5000)->assertCreated();
        $this->move('out', 'withdrawal', 50000)->assertCreated(); // bukan biaya

        $today = now($this->shop->tenant->timezone)->toDateString(); // hari bisnis = tanggal lokal kedai
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)
            ->assertJsonPath('data.gross_profit', 60000)
            ->assertJsonPath('data.expenses.total', 20000)
            ->assertJsonPath('data.expenses.by_category.0', ['key' => 'ingredients', 'label' => 'Belanja bahan', 'total' => 15000])
            ->assertJsonPath('data.expenses.withdrawals', 50000)
            ->assertJsonPath('data.net_profit', 40000);
    }
}
