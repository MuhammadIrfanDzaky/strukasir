<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Category;
use App\Models\Product;
use App\Models\Shift;
use App\Services\ShiftService;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class CreditTest extends TestCase
{
    private object $shop;

    private string $cashier;

    private string $owner;

    private Product $latte;

    private string $customerId;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('Warung');
        $this->cashier = $this->pinLogin($this->shop);
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->latte = $this->tenancy()->run($this->shop->tenant->id, function () {
            $c = Category::create(['name' => 'Kopi']);

            return Product::create(['category_id' => $c->id, 'name' => 'Kopi', 'price' => 20000]);
        });
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 100000])->assertCreated();
        $this->customerId = $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Pak Budi', 'phone' => '081200000001'])->json('data.id');
    }

    private function order(int $qty = 1, ?string $customerId = 'self'): string
    {
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => $qty, 'modifier_ids' => []]],
            'expected_total' => 20000 * $qty,
            'customer_id' => $customerId === 'self' ? $this->customerId : $customerId,
        ])->assertOk();

        return $id;
    }

    private function pay(string $id, array $payments, int $total, ?array $approval = null, ?string $token = null)
    {
        return $this->api('POST', "/api/v1/orders/{$id}/pay", $token ?? $this->cashier, [
            'payments' => array_map(fn ($p) => ['id' => (string) Str::uuid(), ...$p], $payments),
            'expected_total' => $total,
            'approval' => $approval,
        ]);
    }

    private function kasbon(int $qty = 1): string
    {
        $id = $this->order($qty);
        $this->pay($id, [['method' => 'credit', 'amount' => 20000 * $qty]], 20000 * $qty)->assertOk();

        return $id;
    }

    private function balance(): ?int
    {
        return $this->api('GET', '/api/v1/customers?q=Budi', $this->cashier)->json('data.0.credit_balance');
    }

    private function repay(int $amount, array $extra = [], ?string $token = null)
    {
        return $this->api('POST', "/api/v1/customers/{$this->customerId}/credit-repayments", $token ?? $this->cashier, [
            'id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => $amount, ...$extra,
        ]);
    }

    private function shift(): array
    {
        return $this->tenancy()->run($this->shop->tenant->id, fn () => app(ShiftService::class)
            ->summary(Shift::query()->whereNull('closed_at')->firstOrFail()));
    }

    public function test_member_pays_with_credit_and_cash_drawer_is_untouched(): void
    {
        $id = $this->order(2);
        $this->pay($id, [['method' => 'credit', 'amount' => 40000]], 40000)
            ->assertOk()
            ->assertJsonPath('data.status', 'paid')
            ->assertJsonPath('data.credit', ['amount' => 40000, 'balance' => 40000]);

        $this->assertSame(40000, $this->balance());
        $summary = $this->shift();
        $this->assertSame(40000, $summary['by_method']['credit']);
        $this->assertSame(100000, $summary['expected_cash']);
        $this->api('GET', '/api/v1/customers?q=Budi', $this->cashier)->assertJsonPath('data.0.credit_limit', 500000);
    }

    public function test_split_cash_and_credit_and_member_required(): void
    {
        $id = $this->order(2);
        $this->pay($id, [['method' => 'cash', 'amount' => 15000, 'tendered' => 15000], ['method' => 'credit', 'amount' => 25000]], 40000)->assertOk();
        $this->assertSame(25000, $this->balance());

        $anon = $this->order(1, null);
        $this->pay($anon, [['method' => 'credit', 'amount' => 20000]], 20000)->assertUnprocessable()->assertJsonValidationErrors('payments');
    }

    public function test_over_limit_needs_owner_pin(): void
    {
        $this->api('PUT', "/api/v1/customers/{$this->customerId}/credit-limit", $this->owner, ['credit_limit' => 30000])
            ->assertOk()->assertJsonPath('data.credit_limit', 30000)->assertJsonPath('data.credit_limit_custom', true);

        $id = $this->order(2);
        $this->pay($id, [['method' => 'credit', 'amount' => 40000]], 40000)->assertUnprocessable()->assertJsonValidationErrors('approval');
        $this->pay($id, [['method' => 'credit', 'amount' => 40000]], 40000, ['user_id' => $this->shop->owner->id, 'pin' => '000000'])
            ->assertUnprocessable();
        $this->pay($id, [['method' => 'credit', 'amount' => 40000]], 40000, ['user_id' => $this->shop->owner->id, 'pin' => self::PIN])->assertOk();
        $this->assertTrue($this->tenancy()->run($this->shop->tenant->id, fn () => AuditLog::where('action', 'credit.over_limit_approved')->exists()));

        // Owner sendiri tidak perlu PIN; batas "tanpa batas" di kedai berlaku bila batas pelanggan dilepas.
        $this->pay($this->order(), [['method' => 'credit', 'amount' => 20000]], 20000, token: $this->owner)->assertOk();
        $this->api('PUT', "/api/v1/customers/{$this->customerId}/credit-limit", $this->owner, ['credit_limit' => null])->assertOk();
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['credit_default_limit' => null])->assertOk()->assertJsonPath('data.credit_default_limit', null);
        $this->pay($this->order(30), [['method' => 'credit', 'amount' => 600000]], 600000)->assertOk();
    }

    public function test_repayment_goes_into_cash_drawer_and_cannot_exceed_debt(): void
    {
        $this->kasbon(2);
        $id = (string) Str::uuid();
        $this->repay(15000, ['id' => $id, 'tendered' => 20000])->assertCreated()
            ->assertJsonPath('data.change', 5000)->assertJsonPath('data.balance', 25000);
        $this->repay(15000, ['id' => $id, 'tendered' => 20000])->assertCreated()->assertJsonPath('data.balance', 25000); // kirim ulang aman

        $this->repay(30000)->assertUnprocessable()->assertJsonValidationErrors('amount');
        $this->repay(5000, ['method' => 'qris'])->assertCreated()->assertJsonPath('data.balance', 20000);

        $summary = $this->shift();
        $this->assertSame(['cash' => 15000, 'debit' => 0, 'qris' => 5000], $summary['credit_repayments']);
        $this->assertSame(115000, $summary['expected_cash']);
    }

    public function test_owner_reverses_wrong_repayment_once(): void
    {
        $this->kasbon();
        $repayment = $this->repay(20000)->json('data.id');
        $this->assertSame(0, $this->balance());

        $url = "/api/v1/customers/{$this->customerId}/credit-repayments/{$repayment}/reverse";
        $this->api('POST', $url, $this->cashier, ['reason' => 'Salah pelanggan'])->assertForbidden();
        $this->api('POST', $url, $this->owner, ['reason' => 'Salah pelanggan'])->assertOk()->assertJsonPath('data.balance', 20000);
        $this->api('POST', $url, $this->owner, ['reason' => 'Salah pelanggan'])->assertStatus(409);
        $this->assertSame(100000, $this->shift()['expected_cash']);

        $history = $this->api('GET', "/api/v1/customers/{$this->customerId}", $this->owner)->json('data.credit_history');
        $this->assertEqualsCanonicalizing(['charge', 'repayment', 'reversal'], array_column($history, 'kind'));
        $this->assertTrue(collect($history)->firstWhere('kind', 'repayment')['reversed']);
    }

    public function test_void_reduces_debt_and_debt_blocks_anonymize(): void
    {
        $id = $this->kasbon();
        $this->kasbon();
        $this->api('POST', "/api/v1/customers/{$this->customerId}/anonymize", $this->owner)->assertUnprocessable();

        $this->api('POST', "/api/v1/orders/{$id}/void", $this->owner, ['reason' => 'Salah input'])->assertOk();
        $this->assertSame(20000, $this->balance());
        $this->assertSame(100000, $this->shift()['expected_cash'], 'refund kasbon tidak mengeluarkan uang laci');

        $this->repay(20000)->assertCreated();
        $this->api('POST', "/api/v1/customers/{$this->customerId}/anonymize", $this->owner)->assertOk();
    }

    public function test_debtor_list_and_reports(): void
    {
        $this->kasbon(2);
        $this->repay(10000)->assertCreated();
        $other = $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Bu Sari', 'phone' => '081200000002'])->json('data.id');

        $names = fn (string $q) => collect($this->api('GET', "/api/v1/customers?{$q}", $this->owner)->json('data'))->pluck('name')->all();
        $this->assertSame(['Pak Budi'], $names('segment=debt'));
        $this->assertSame(['Pak Budi', 'Bu Sari'], $names('sort=debt'));
        $this->assertNotNull($other);

        $today = now()->toDateString();
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)
            ->assertJsonPath('data.by_method.credit', 40000)
            ->assertJsonPath('data.credit.issued', 40000)
            ->assertJsonPath('data.credit.repaid', 10000)
            ->assertJsonPath('data.credit.outstanding', 30000)
            ->assertJsonPath('data.credit.debtors', 1)
            ->assertJsonPath('data.credit.top.0.name', 'Pak Budi');
    }

    public function test_feature_off_blocks_credit(): void
    {
        $this->kasbon();
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['customer_credit' => false]])->assertOk();

        $this->assertNull($this->balance());
        $this->pay($this->order(), [['method' => 'credit', 'amount' => 20000]], 20000)->assertUnprocessable()->assertJsonValidationErrors('payments');
        $this->repay(1000)->assertForbidden();
    }

    public function test_repayments_need_open_shift_and_are_append_only(): void
    {
        $this->kasbon();
        $this->api('POST', '/api/v1/shifts/close', $this->cashier, ['counted_cash' => 100000])->assertOk();
        $this->repay(1000)->assertUnprocessable()->assertJsonValidationErrors('shift');

        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 0])->assertCreated();
        $this->repay(1000)->assertCreated();
        $this->expectException(QueryException::class);
        $this->tenancy()->run($this->shop->tenant->id, fn () => DB::table('credit_repayments')->update(['amount' => 1]));
    }
}
