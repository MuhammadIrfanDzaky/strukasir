<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\LoyaltyEntry;
use App\Models\Product;
use Illuminate\Database\QueryException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class LoyaltyTest extends TestCase
{
    private object $shop;

    private string $cashier;

    private string $owner;

    private Product $latte;

    private Product $snack;

    private Category $kopi;

    private string $customerId;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->cashier = $this->pinLogin($this->shop);
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        [$this->kopi, $this->latte, $this->snack] = $this->inShop(function () {
            $kopi = Category::create(['name' => 'Kopi']);
            $makanan = Category::create(['name' => 'Makanan']);

            return [
                $kopi,
                Product::create(['category_id' => $kopi->id, 'name' => 'Latte', 'price' => 20000]),
                Product::create(['category_id' => $makanan->id, 'name' => 'Roti', 'price' => 10000]),
            ];
        });
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 100000])->assertCreated();
        $this->customerId = $this->api('POST', '/api/v1/customers', $this->cashier, ['name' => 'Andi', 'phone' => '081200000001'])->json('data.id');
    }

    private function inShop(callable $fn): mixed
    {
        return $this->tenancy()->run($this->shop->tenant->id, $fn);
    }

    /** Program contoh: 1 stempel per kopi; hadiah gratis Latte (3), potongan Rp5.000 (2), potongan 10% (5). */
    private function configure(array $override = [], ?array $rewards = null)
    {
        return $this->api('PUT', '/api/v1/settings/loyalty', $this->owner, [
            'active' => true,
            'name' => 'BerryCard',
            'earn_mode' => 'per_item',
            'category_ids' => [$this->kopi->id],
            'rewards' => $rewards ?? [
                ['name' => 'Gratis Latte', 'cost' => 3, 'type' => 'free_product', 'product_id' => $this->latte->id],
                ['name' => 'Potongan 5rb', 'cost' => 2, 'type' => 'amount', 'value' => 5000],
                ['name' => 'Diskon 10%', 'cost' => 5, 'type' => 'percent', 'value' => 1000],
            ],
            ...$override,
        ]);
    }

    private function reward(string $name): string
    {
        return collect($this->api('GET', '/api/v1/settings/loyalty', $this->owner)->json('data.rewards'))->firstWhere('name', $name)['id'];
    }

    private function line(Product $product, int $qty = 1): array
    {
        return ['id' => (string) Str::uuid(), 'product_id' => $product->id, 'qty' => $qty, 'modifier_ids' => []];
    }

    private function save(string $id, array $items, int $total, array $extra = [])
    {
        return $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => $items, 'expected_total' => $total, 'customer_id' => $this->customerId, ...$extra,
        ]);
    }

    private function pay(string $id, int $total)
    {
        return $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => $total, 'tendered' => $total]],
            'expected_total' => $total,
        ]);
    }

    private function sell(array $items, int $total, array $extra = [])
    {
        $id = (string) Str::uuid();
        $this->save($id, $items, $total, $extra)->assertOk();

        return $this->pay($id, $total)->assertOk();
    }

    private function balance(): ?int
    {
        return $this->api('GET', '/api/v1/customers?q=Andi', $this->cashier)->json('data.0.loyalty_balance');
    }

    private function giveUnits(int $units): void
    {
        $this->api('POST', "/api/v1/customers/{$this->customerId}/loyalty-adjust", $this->owner, ['units' => $units, 'note' => 'Kartu kertas'])->assertOk();
    }

    // ─────────────── pengaturan ───────────────

    public function test_owner_configures_program_and_tablets_receive_it(): void
    {
        $this->configure()->assertOk()
            ->assertJsonPath('data.program.unit', 'stempel')
            ->assertJsonCount(3, 'data.rewards');

        $menu = $this->api('GET', '/api/v1/menu', $this->cashier)->assertOk();
        $menu->assertJsonPath('loyalty.name', 'BerryCard')
            ->assertJsonPath('loyalty.category_ids', [$this->kopi->id])
            ->assertJsonPath('loyalty.rewards.0.cost', 2); // urut harga stempel

        // Hadiah yang dibuang dari daftar dinonaktifkan, bukan dihapus.
        $this->configure(rewards: [['name' => 'Potongan 5rb', 'cost' => 2, 'type' => 'amount', 'value' => 5000]])->assertOk()->assertJsonCount(1, 'data.rewards');
        // (tanpa id = hadiah baru) → 4 baris, hanya 1 yang aktif.
        $this->assertSame([4, 1], $this->inShop(fn () => [DB::table('loyalty_rewards')->count(), DB::table('loyalty_rewards')->where('active', true)->count()]));

        $this->api('PUT', '/api/v1/settings/loyalty', $this->cashier, [])->assertForbidden();
    }

    public function test_validation_of_program_and_rewards(): void
    {
        $this->configure(['earn_mode' => 'per_amount'])->assertUnprocessable()->assertJsonValidationErrors('earn_per_amount');
        $this->configure(rewards: [])->assertUnprocessable()->assertJsonValidationErrors('rewards');
        $this->configure(rewards: [['name' => 'X', 'cost' => 1, 'type' => 'percent', 'value' => 20000]])
            ->assertUnprocessable()->assertJsonValidationErrors('rewards.0.value');
        $this->configure(rewards: [['name' => 'X', 'cost' => 1, 'type' => 'free_product']])
            ->assertUnprocessable()->assertJsonValidationErrors('rewards.0.product_id');
        // Program boleh disimpan mati tanpa hadiah.
        $this->configure(['active' => false], [])->assertOk();
        $this->assertNull($this->api('GET', '/api/v1/menu', $this->cashier)->json('loyalty'));
    }

    // ─────────────── dapat stempel / poin ───────────────

    public function test_stamps_per_item_only_for_chosen_categories(): void
    {
        $this->configure()->assertOk();
        $this->sell([$this->line($this->latte, 2), $this->line($this->snack)], 50000)
            ->assertJsonPath('data.loyalty', ['program' => 'BerryCard', 'unit' => 'stempel', 'earned' => 2, 'redeemed' => 0, 'balance' => 2]);
        $this->assertSame(2, $this->balance());

        // Tanpa member: tidak ada stempel.
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, ['items' => [$this->line($this->latte)], 'expected_total' => 20000])->assertOk();
        $this->pay($id, 20000)->assertOk()->assertJsonPath('data.loyalty', null);
    }

    public function test_points_per_amount_and_stamp_per_order(): void
    {
        $this->configure(['earn_mode' => 'per_amount', 'earn_per_amount' => 10000])->assertOk()->assertJsonPath('data.program.unit', 'poin');
        $this->sell([$this->line($this->latte, 2), $this->line($this->snack)], 50000)->assertJsonPath('data.loyalty.earned', 5);

        $this->configure(['earn_mode' => 'per_order', 'earn_min_order' => 30000])->assertOk();
        $this->sell([$this->line($this->latte)], 20000)->assertJsonPath('data.loyalty', null); // di bawah minimal
        $this->sell([$this->line($this->latte, 2)], 40000)->assertJsonPath('data.loyalty.earned', 1);
        $this->assertSame(6, $this->balance());
    }

    // ─────────────── tukar hadiah ───────────────

    public function test_free_product_reward_discounts_one_portion_without_owner_approval(): void
    {
        $this->configure()->assertOk();
        $this->giveUnits(3);
        $item = $this->line($this->latte, 2);
        $reward = $this->reward('Gratis Latte');

        $id = (string) Str::uuid();
        $this->save($id, [$item], 20000, ['reward' => ['id' => $reward, 'item_id' => $item['id']]])
            ->assertOk()
            ->assertJsonPath('data.reward.name', 'Gratis Latte')
            ->assertJsonPath('data.reward.discount', 20000)
            ->assertJsonPath('data.items.0.discount', null) // bukan diskon manual
            ->assertJsonPath('data.items.0.discount_total', 20000)
            ->assertJsonPath('data.grand_total', 20000);

        // Porsi gratis tidak menghasilkan stempel: 2 latte − 1 gratis = 1.
        $this->pay($id, 20000)->assertOk()->assertJsonPath('data.loyalty.redeemed', 3)->assertJsonPath('data.loyalty.earned', 1)
            ->assertJsonPath('data.loyalty.balance', 1);
    }

    public function test_reward_needs_member_balance_and_product_in_cart(): void
    {
        $this->configure()->assertOk();
        $reward = $this->reward('Gratis Latte');
        $item = $this->line($this->latte);

        $this->save((string) Str::uuid(), [$item], 0, ['reward' => ['id' => $reward, 'item_id' => $item['id']]])
            ->assertUnprocessable()->assertJsonValidationErrors('reward');
        $this->giveUnits(3);
        $roti = $this->line($this->snack);
        $this->save((string) Str::uuid(), [$roti], 0, ['reward' => ['id' => $reward, 'item_id' => $roti['id']]])
            ->assertUnprocessable()->assertJsonValidationErrors('reward');
        $this->api('PUT', '/api/v1/orders/'.Str::uuid(), $this->cashier, [
            'items' => [$item], 'expected_total' => 0, 'reward' => ['id' => $reward, 'item_id' => $item['id']],
        ])->assertUnprocessable()->assertJsonValidationErrors('reward'); // tanpa member
    }

    public function test_amount_and_percent_rewards_use_order_discount_and_cannot_stack(): void
    {
        $this->configure()->assertOk();
        $this->giveUnits(7);

        $id = (string) Str::uuid();
        $this->save($id, [$this->line($this->snack)], 5000, ['reward' => ['id' => $this->reward('Potongan 5rb')]])
            ->assertOk()->assertJsonPath('data.order_discount', null)->assertJsonPath('data.reward.discount', 5000);
        $this->save($id, [$this->line($this->snack)], 5000, [
            'reward' => ['id' => $this->reward('Potongan 5rb')], 'order_discount' => ['type' => 'amount', 'value' => 1000],
        ])->assertUnprocessable()->assertJsonValidationErrors('order_discount');
        $this->pay($id, 5000)->assertOk()->assertJsonPath('data.loyalty.redeemed', 2);

        // Potongan Rp melebihi belanja dibatasi sebesar subtotal.
        $this->configure(rewards: [['name' => 'Potongan 50rb', 'cost' => 1, 'type' => 'amount', 'value' => 50000]])->assertOk();
        $this->save((string) Str::uuid(), [$this->line($this->snack)], 0, ['reward' => ['id' => $this->reward('Potongan 50rb')]])
            ->assertOk()->assertJsonPath('data.grand_total', 0);

        $this->configure()->assertOk();
        $this->sell([$this->line($this->latte, 2)], 36000, ['reward' => ['id' => $this->reward('Diskon 10%')]])
            ->assertJsonPath('data.reward.discount', 4000)->assertJsonPath('data.loyalty.redeemed', 5);
    }

    public function test_same_stamps_cannot_be_spent_twice_by_two_open_bills(): void
    {
        $this->configure()->assertOk();
        $this->giveUnits(2);
        $reward = ['reward' => ['id' => $this->reward('Potongan 5rb')]];
        [$a, $b] = [(string) Str::uuid(), (string) Str::uuid()];
        $this->save($a, [$this->line($this->snack)], 5000, $reward)->assertOk();
        $this->save($b, [$this->line($this->snack)], 5000, $reward)->assertOk();

        $this->pay($a, 5000)->assertOk();
        $this->pay($b, 5000)->assertUnprocessable()->assertJsonValidationErrors('reward');
        $this->assertSame(0, $this->balance());
        $this->api('GET', "/api/v1/orders/{$b}", $this->cashier)->assertJsonPath('data.status', 'open')->assertJsonCount(0, 'data.payments');
    }

    public function test_void_returns_reward_and_removes_earned_stamps(): void
    {
        $this->configure()->assertOk();
        $this->giveUnits(2);
        $id = $this->sell([$this->line($this->latte, 2)], 35000, ['reward' => ['id' => $this->reward('Potongan 5rb')]])->json('data.id');
        $this->assertSame(2, $this->balance()); // 2 − 2 + 2

        $this->api('POST', "/api/v1/orders/{$id}/void", $this->owner, ['reason' => 'Salah input'])->assertOk();
        $this->assertSame(2, $this->balance()); // tukar dikembalikan, stempel dari order ditarik
        $this->api('POST', "/api/v1/orders/{$id}/void", $this->owner, ['reason' => 'Salah input'])->assertOk();
        $this->assertSame(2, $this->balance(), 'void ulang tidak membatalkan dua kali');
    }

    // ─────────────── hangus, penyesuaian, laporan ───────────────

    public function test_balance_expires_after_inactivity(): void
    {
        $this->configure(['expiry_months' => 6])->assertOk();
        // Saldo lama dari 7 bulan lalu (buku append-only: dicatat langsung dengan tanggal lampau).
        $this->inShop(fn () => LoyaltyEntry::create([
            'customer_id' => $this->customerId, 'kind' => 'adjust', 'units' => 4, 'note' => 'lama',
            'created_at' => Carbon::now()->subMonths(7),
        ]));

        $this->assertSame(0, $this->balance());
        $this->sell([$this->line($this->latte)], 20000)->assertJsonPath('data.loyalty.balance', 1);
        $kinds = $this->inShop(fn () => LoyaltyEntry::orderBy('created_at')->pluck('kind')->all());
        $this->assertEqualsCanonicalizing(['adjust', 'expire', 'earn'], $kinds);
    }

    public function test_owner_adjusts_balance_with_reason(): void
    {
        $this->configure()->assertOk();
        $this->api('POST', "/api/v1/customers/{$this->customerId}/loyalty-adjust", $this->owner, ['units' => 5, 'note' => 'Pindahan kartu kertas'])
            ->assertOk()->assertJsonPath('data.balance', 5);
        $this->api('POST', "/api/v1/customers/{$this->customerId}/loyalty-adjust", $this->owner, ['units' => -9, 'note' => 'Koreksi'])
            ->assertUnprocessable()->assertJsonValidationErrors('units');
        $this->api('POST', "/api/v1/customers/{$this->customerId}/loyalty-adjust", $this->owner, ['units' => 1])
            ->assertUnprocessable()->assertJsonValidationErrors('note');
        $this->api('POST', "/api/v1/customers/{$this->customerId}/loyalty-adjust", $this->cashier, ['units' => 1, 'note' => 'x'])->assertForbidden();

        $this->api('GET', "/api/v1/customers/{$this->customerId}", $this->owner)
            ->assertJsonPath('data.loyalty_balance', 5)
            ->assertJsonPath('data.loyalty_entries.0.kind', 'adjust')
            ->assertJsonPath('data.loyalty_entries.0.note', 'Pindahan kartu kertas');
    }

    public function test_ledger_is_append_only(): void
    {
        $this->configure()->assertOk();
        $this->giveUnits(5);
        $this->expectException(QueryException::class);
        $this->inShop(fn () => DB::table('loyalty_entries')->update(['units' => 500]));
    }

    public function test_reports_show_units_and_popular_rewards(): void
    {
        $this->configure()->assertOk();
        $this->giveUnits(2);
        $this->sell([$this->line($this->latte, 2)], 35000, ['reward' => ['id' => $this->reward('Potongan 5rb')]]);
        $today = now()->toDateString();
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)
            ->assertJsonPath('data.loyalty.earned', 2)
            ->assertJsonPath('data.loyalty.redeemed', 2)
            ->assertJsonPath('data.loyalty.rewards.0', ['name' => 'Potongan 5rb', 'count' => 1, 'discount' => 5000]);
    }

    public function test_feature_off_hides_program_and_blocks_rewards(): void
    {
        $this->configure()->assertOk();
        $this->giveUnits(5);
        $reward = $this->reward('Potongan 5rb');
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['loyalty' => false]])->assertOk();

        $this->assertNull($this->api('GET', '/api/v1/menu', $this->cashier)->json('loyalty'));
        $this->api('GET', '/api/v1/settings/loyalty', $this->owner)->assertForbidden();
        $this->assertNull($this->balance());
        $this->save((string) Str::uuid(), [$this->line($this->snack)], 5000, ['reward' => ['id' => $reward]])
            ->assertUnprocessable()->assertJsonValidationErrors('reward');
        $this->sell([$this->line($this->latte)], 20000)->assertJsonPath('data.loyalty', null); // tidak dapat stempel
    }

    public function test_rewards_of_another_shop_cannot_be_used(): void
    {
        $other = $this->makeShop('Lain');
        $otherOwner = $this->pinLogin($other, $other->owner);
        $foreign = $this->api('PUT', '/api/v1/settings/loyalty', $otherOwner, [
            'active' => true, 'name' => 'Lain', 'earn_mode' => 'per_order',
            'rewards' => [['name' => 'Potongan', 'cost' => 1, 'type' => 'amount', 'value' => 5000]],
        ])->assertOk()->json('data.rewards.0.id');

        $this->configure()->assertOk();
        $this->giveUnits(5);
        $this->save((string) Str::uuid(), [$this->line($this->snack)], 5000, ['reward' => ['id' => $foreign]])
            ->assertUnprocessable()->assertJsonValidationErrors('reward');
    }
}
