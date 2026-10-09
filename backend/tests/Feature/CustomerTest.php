<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Category;
use App\Models\Customer;
use App\Models\Product;
use App\Services\TenantDataService;
use App\Support\PhoneNumber;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class CustomerTest extends TestCase
{
    private object $shop;

    private string $cashier;

    private string $owner;

    private Product $latte;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->cashier = $this->pinLogin($this->shop);
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->latte = $this->inShop(function () {
            $kopi = Category::create(['name' => 'Kopi']);

            return Product::create(['category_id' => $kopi->id, 'name' => 'Latte', 'price' => 20000]);
        });
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 100000])->assertCreated();
    }

    private function inShop(callable $fn): mixed
    {
        return $this->tenancy()->run($this->shop->tenant->id, $fn);
    }

    private function register(array $data, ?string $token = null)
    {
        return $this->api('POST', '/api/v1/customers', $token ?? $this->cashier, $data);
    }

    /** Order lunas 1× Latte (20.000) untuk pelanggan; kembalikan ID order. */
    private function sell(?string $customerId, int $qty = 1, array $extra = []): string
    {
        $id = (string) Str::uuid();
        $total = 20000 * $qty;
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => $qty, 'modifier_ids' => []]],
            'expected_total' => $total,
            'customer_id' => $customerId,
            ...$extra,
        ])->assertOk();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => $total, 'tendered' => $total]],
            'expected_total' => $total,
        ])->assertOk();

        return $id;
    }

    private function setPhoneRequired(bool $required): void
    {
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['customer_phone_required' => $required])
            ->assertOk()->assertJsonPath('data.customer_phone_required', $required);
    }

    // ─────────────── daftar & data ───────────────

    public function test_phone_numbers_are_normalized(): void
    {
        $this->assertSame('+6281234567890', PhoneNumber::normalize('0812-3456-7890'));
        $this->assertSame('+6281234567890', PhoneNumber::normalize('62 812 3456 7890'));
        $this->assertSame('+6281234567890', PhoneNumber::normalize('+62 812.3456.7890'));
        $this->assertSame('+6281234567890', PhoneNumber::normalize('81234567890'));
        $this->assertNull(PhoneNumber::normalize('12'));
        $this->assertNull(PhoneNumber::normalize('abc'));
        $this->assertSame('0812****7890', PhoneNumber::mask('+6281234567890'));
    }

    public function test_cashier_registers_customers_with_sequential_codes_and_masked_phone(): void
    {
        $this->register(['name' => '  Andi   Saputra ', 'phone' => '0812-3456-7890', 'note' => 'Alergi susu'])
            ->assertCreated()
            ->assertJsonPath('data.code', 'M0001')
            ->assertJsonPath('data.name', 'Andi Saputra')
            ->assertJsonPath('data.phone', '0812****7890')
            ->assertJsonPath('data.note', 'Alergi susu')
            ->assertJsonMissingPath('data.total_spent')
            ->assertJsonMissingPath('data.birth_date');

        $this->register(['name' => 'Budi', 'phone' => '0813 1111 2222', 'birth_date' => '1990-05-01'], $this->owner)
            ->assertCreated()
            ->assertJsonPath('data.code', 'M0002')
            ->assertJsonPath('data.phone', '+6281311112222')
            ->assertJsonPath('data.birth_date', '1990-05-01');
    }

    public function test_code_and_tenant_cannot_be_set_from_request(): void
    {
        $other = $this->makeShop('Lain');
        $this->register(['name' => 'Citra', 'phone' => '081200000001', 'code' => 'VIP1', 'tenant_id' => $other->tenant->id,
            'anonymized_at' => now()->toIso8601String()])
            ->assertCreated()->assertJsonPath('data.code', 'M0001');

        $customer = $this->inShop(fn () => Customer::firstOrFail());
        $this->assertSame($this->shop->tenant->id, $customer->tenant_id);
        $this->assertNull($customer->anonymized_at);
    }

    public function test_phone_is_required_by_default_and_owner_can_make_it_optional(): void
    {
        $this->register(['name' => 'Dewi'])->assertUnprocessable()->assertJsonValidationErrors('phone');
        $this->assertTrue($this->api('GET', '/api/v1/menu', $this->cashier)->json('customer_phone_required'));

        $this->setPhoneRequired(false);
        $this->assertFalse($this->api('GET', '/api/v1/menu', $this->cashier)->json('customer_phone_required'));
        $this->register(['name' => 'Dewi'])->assertCreated()->assertJsonPath('data.phone', null);
        $this->register(['name' => 'Dewi'])->assertCreated()->assertJsonPath('data.code', 'M0002'); // nama boleh kembar
    }

    public function test_same_phone_in_any_format_is_rejected(): void
    {
        $this->register(['name' => 'Eka', 'phone' => '081234567890'])->assertCreated();
        $this->register(['name' => 'Eko', 'phone' => '+62 812-3456-7890'])
            ->assertUnprocessable()->assertJsonValidationErrors('phone');
        $this->register(['name' => 'Eko', 'phone' => '12'])
            ->assertUnprocessable()->assertJsonValidationErrors('phone');
    }

    public function test_owner_updates_customer_and_audit_has_no_personal_data(): void
    {
        $id = $this->register(['name' => 'Fajar', 'phone' => '081200000002'])->json('data.id');

        $this->api('PUT', "/api/v1/customers/{$id}", $this->owner, ['name' => 'Fajar Nugraha', 'phone' => '081200000002', 'birth_date' => '1995-02-03'])
            ->assertOk()->assertJsonPath('data.name', 'Fajar Nugraha')->assertJsonPath('data.birth_date', '1995-02-03');
        // No HP sendiri tidak dianggap bentrok saat mengubah data.
        $this->api('PUT', "/api/v1/customers/{$id}", $this->owner, ['name' => 'Fajar N', 'phone' => '0812 0000 0002'])->assertOk();

        $logs = $this->inShop(fn () => AuditLog::where('action', 'like', 'customer.%')->get());
        $this->assertSame(['customer.created', 'customer.updated', 'customer.updated'], $logs->pluck('action')->all());
        $this->assertStringNotContainsString('Fajar', $logs->toJson());
        $this->assertStringNotContainsString('812', $logs->toJson());
        $this->assertContains('birth_date', $logs[1]->after['fields']);
    }

    // ─────────────── cari & kelompok ───────────────

    public function test_search_by_name_code_or_phone_fragment(): void
    {
        $this->register(['name' => 'Gita Permata', 'phone' => '081277778888'])->assertCreated();
        $this->register(['name' => 'Hendra', 'phone' => '085611112222'])->assertCreated();

        $names = fn (string $q) => collect($this->api('GET', '/api/v1/customers?q='.urlencode($q), $this->cashier)->json('data'))->pluck('name')->all();
        $this->assertSame(['Gita Permata'], $names('perm'));
        $this->assertSame(['Hendra'], $names('m0002'));
        $this->assertSame(['Gita Permata'], $names('0812 7777'));
        $this->assertSame(['Hendra'], $names('2222'));
        $this->assertSame(['Gita Permata', 'Hendra'], $names(''));
        $this->assertSame([], $names('%'));
    }

    public function test_list_is_paginated_and_capped(): void
    {
        $this->setPhoneRequired(false);
        foreach (range(1, 3) as $i) {
            $this->register(['name' => "Pelanggan {$i}"])->assertCreated();
        }
        $this->api('GET', '/api/v1/customers?per_page=2', $this->cashier)
            ->assertOk()->assertJsonCount(2, 'data')->assertJsonPath('meta.total', 3)->assertJsonPath('meta.last_page', 2);
        $this->api('GET', '/api/v1/customers?per_page=500', $this->cashier)->assertUnprocessable();
    }

    public function test_segments_new_loyal_lost(): void
    {
        $this->setPhoneRequired(false);
        $loyal = $this->register(['name' => 'Setia'])->json('data.id');
        $lost = $this->register(['name' => 'Hilang'])->json('data.id');
        $this->register(['name' => 'Baru'])->assertCreated();

        foreach (range(1, 5) as $_) {
            $this->sell($loyal);
        }
        $this->sell($lost);
        // Pelanggan "Hilang" terdaftar & terakhir belanja 40 hari lalu.
        $this->inShop(function () use ($lost) {
            $past = Carbon::now()->subDays(40);
            Customer::whereKey($lost)->update(['created_at' => $past]);
            DB::table('orders')->where('customer_id', $lost)->update(['paid_at' => $past]);
        });

        $names = fn (string $segment) => collect($this->api('GET', "/api/v1/customers?segment={$segment}", $this->owner)->json('data'))->pluck('name')->all();
        $this->assertSame(['Setia'], $names('loyal'));
        $this->assertSame(['Hilang'], $names('lost'));
        $this->assertSame(['Baru', 'Setia'], $names('new'));

        $this->api('GET', '/api/v1/customers?with_counts=1', $this->owner)
            ->assertJsonPath('meta.segments', ['all' => 3, 'new' => 2, 'loyal' => 1, 'lost' => 1]);
        $top = $this->api('GET', '/api/v1/customers?sort=top', $this->owner)->json('data');
        $this->assertSame(['Setia', 'Hilang', 'Baru'], array_column($top, 'name'));
        $this->assertSame([100000, 20000, 0], array_column($top, 'total_spent'));
    }

    // ─────────────── order ───────────────

    public function test_order_links_customer_and_stats_count_only_paid_orders(): void
    {
        $id = $this->register(['name' => 'Indah', 'phone' => '081233334444'])->json('data.id');

        $orderId = $this->sell($id, 2);
        $this->api('GET', "/api/v1/orders/{$orderId}", $this->cashier)
            ->assertJsonPath('data.customer.code', 'M0001')
            ->assertJsonPath('data.customer_label', 'Indah'); // label kosong → nama member

        $this->sell($id, 1, ['customer_label' => 'Meja 4']);
        $voided = $this->sell($id);
        $this->api('POST', "/api/v1/orders/{$voided}/void", $this->owner, ['reason' => 'Salah input'])->assertOk();

        $this->api('GET', "/api/v1/customers/{$id}", $this->owner)
            ->assertOk()
            ->assertJsonPath('data.visits', 2)
            ->assertJsonPath('data.total_spent', 60000)
            ->assertJsonPath('data.favorites.0', ['name' => 'Latte', 'qty' => 3])
            ->assertJsonCount(3, 'data.recent_orders');

        $this->api('GET', '/api/v1/customers', $this->cashier)->assertJsonPath('data.0.visits', 2);
    }

    public function test_reports_include_member_share_and_new_customers(): void
    {
        $andi = $this->register(['name' => 'Andi', 'phone' => '081200000010'])->json('data.id');
        $budi = $this->register(['name' => 'Budi', 'phone' => '081200000011'])->json('data.id');
        $this->sell($andi, 2);
        $this->sell($andi);
        $this->sell($budi);
        $this->sell(null);
        // Budi sudah pernah belanja sebelum periode ini → pelanggan kembali, bukan baru.
        $this->inShop(fn () => DB::table('orders')->insert(DB::table('orders')->where('customer_id', $budi)->get()->map(fn ($o) => [
            ...(array) $o, 'id' => (string) Str::uuid(), 'number' => 'OLD-1', 'business_date' => now()->subDays(60)->toDateString(),
        ])->all()));

        $today = now()->toDateString();
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)
            ->assertOk()
            ->assertJsonPath('data.customers.orders', 3)
            ->assertJsonPath('data.customers.sales', 80000)
            ->assertJsonPath('data.customers.active', 2)
            ->assertJsonPath('data.customers.new', 1)
            ->assertJsonPath('data.customers.returning', 1)
            ->assertJsonPath('data.customers.top.0.name', 'Andi')
            ->assertJsonPath('data.customers.top.0.sales', 60000);
    }

    // ─────────────── hak akses & isolasi ───────────────

    public function test_cashier_cannot_manage_customers(): void
    {
        $id = $this->register(['name' => 'Joko', 'phone' => '081200000003'])->json('data.id');

        $this->api('GET', "/api/v1/customers/{$id}", $this->cashier)->assertForbidden();
        $this->api('PUT', "/api/v1/customers/{$id}", $this->cashier, ['name' => 'X', 'phone' => '081200000003'])->assertForbidden();
        $this->api('POST', "/api/v1/customers/{$id}/anonymize", $this->cashier)->assertForbidden();
        $this->api('POST', '/api/v1/customers/import', $this->cashier, ['csv' => "Nama\nA"])->assertForbidden();
    }

    public function test_customers_of_another_shop_are_invisible_and_cannot_be_linked(): void
    {
        $other = $this->makeShop('Lain');
        $otherOwner = $this->pinLogin($other, $other->owner);
        $foreign = $this->register(['name' => 'Rahasia', 'phone' => '081299990000'], $otherOwner)->json('data.id');

        $this->assertSame([], $this->api('GET', '/api/v1/customers', $this->owner)->json('data'));
        $this->api('GET', "/api/v1/customers/{$foreign}", $this->owner)->assertNotFound();
        $this->api('PUT', "/api/v1/customers/{$foreign}", $this->owner, ['name' => 'X', 'phone' => '081299990001'])->assertNotFound();
        $this->api('POST', "/api/v1/customers/{$foreign}/anonymize", $this->owner)->assertNotFound();

        $this->api('PUT', '/api/v1/orders/'.Str::uuid(), $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => 1, 'modifier_ids' => []]],
            'expected_total' => 20000,
            'customer_id' => $foreign,
        ])->assertUnprocessable()->assertJsonValidationErrors('customer_id');

        // No HP yang sama boleh dipakai di kedai lain.
        $this->register(['name' => 'Rahasia Juga', 'phone' => '081299990000'])->assertCreated();
    }

    public function test_feature_off_blocks_customer_endpoints_and_new_links(): void
    {
        $id = $this->register(['name' => 'Kiki', 'phone' => '081200000004'])->json('data.id');
        $openId = (string) Str::uuid();
        $item = ['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => 1, 'modifier_ids' => []];
        $this->api('PUT', "/api/v1/orders/{$openId}", $this->cashier, ['items' => [$item], 'expected_total' => 20000, 'customer_id' => $id])->assertOk();

        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['customers' => false, 'loyalty' => false]])->assertOk();
        $this->assertNotContains('customers.view', $this->api('GET', '/api/v1/auth/me', $this->cashier)->json('user.permissions'));

        $this->api('GET', '/api/v1/customers', $this->cashier)->assertForbidden();
        $this->register(['name' => 'Lina', 'phone' => '081200000005'], $this->owner)->assertForbidden();
        $this->api('PUT', '/api/v1/orders/'.Str::uuid(), $this->cashier, [
            'items' => [$item + ['id' => (string) Str::uuid()]], 'expected_total' => 20000, 'customer_id' => $id,
        ])->assertUnprocessable()->assertJsonValidationErrors('customer_id');
        // Open bill lama yang sudah tertaut tetap bisa disimpan ulang.
        $this->api('PUT', "/api/v1/orders/{$openId}", $this->cashier, ['items' => [$item], 'expected_total' => 20000, 'customer_id' => $id])->assertOk();
    }

    // ─────────────── hapus data (UU PDP) ───────────────

    public function test_anonymize_erases_personal_data_but_keeps_sales(): void
    {
        $id = $this->register(['name' => 'Mira', 'phone' => '081200000006', 'note' => 'Suka less sugar'])->json('data.id');
        $orderId = $this->sell($id);
        $labelled = $this->sell($id, 1, ['customer_label' => 'Meja 7']);

        $this->api('POST', "/api/v1/customers/{$id}/anonymize", $this->owner)->assertOk();

        $customer = $this->inShop(fn () => Customer::findOrFail($id));
        $this->assertSame('Pelanggan dihapus', $customer->name);
        $this->assertNull($customer->phone);
        $this->assertNull($customer->note);
        $this->assertNotNull($customer->anonymized_at);

        $this->api('GET', "/api/v1/orders/{$orderId}", $this->owner)
            ->assertJsonPath('data.customer_label', null)
            ->assertJsonPath('data.customer.anonymized', true)
            ->assertJsonPath('data.grand_total', 20000);
        $this->api('GET', "/api/v1/orders/{$labelled}", $this->owner)->assertJsonPath('data.customer_label', 'Meja 7');

        $this->assertSame([], $this->api('GET', '/api/v1/customers', $this->owner)->json('data'));
        $this->api('GET', "/api/v1/customers/{$id}", $this->owner)->assertNotFound();
        $this->api('PUT', '/api/v1/orders/'.Str::uuid(), $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => 1, 'modifier_ids' => []]],
            'expected_total' => 20000, 'customer_id' => $id,
        ])->assertUnprocessable();
        // Nomornya bebas dipakai lagi.
        $this->register(['name' => 'Mira Baru', 'phone' => '081200000006'])->assertCreated();

        $today = now()->toDateString();
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)->assertJsonPath('data.customers.orders', 2);
        $log = $this->inShop(fn () => AuditLog::where('action', 'customer.anonymized')->firstOrFail());
        $this->assertStringNotContainsString('Mira', json_encode($log->after));
    }

    // ─────────────── import CSV ───────────────

    public function test_import_creates_and_updates_by_phone(): void
    {
        $this->register(['name' => 'Nanda', 'phone' => '081200000007'])->assertCreated();
        $csv = "Nama Pelanggan;No HP;Tanggal Lahir;Catatan\n"
            ."Nanda Putri;+62 812-0000-0007;31/12/1990;Langganan\n"
            ."Oki;0857 1234 5678;;\n";

        $this->api('POST', '/api/v1/customers/import', $this->owner, ['csv' => $csv, 'dry_run' => true])
            ->assertOk()->assertJsonPath('data.created', 1)->assertJsonPath('data.updated', 1)->assertJsonPath('data.saved', false);
        $this->assertSame(1, $this->inShop(fn () => Customer::count()));

        $this->api('POST', '/api/v1/customers/import', $this->owner, ['csv' => $csv])->assertOk()->assertJsonPath('data.saved', true);
        $all = $this->inShop(fn () => Customer::orderBy('code')->get());
        $this->assertSame(['M0001', 'M0002'], $all->pluck('code')->all());
        $this->assertSame('Nanda Putri', $all[0]->name);
        $this->assertSame('1990-12-31', $all[0]->birth_date->toDateString());
        $this->assertSame('+6285712345678', $all[1]->phone);
    }

    public function test_import_with_errors_saves_nothing(): void
    {
        $csv = "Nama,No HP,Tanggal lahir\n"
            ."Putri,081200000008,\n"
            .",081200000009,\n"
            ."Rizky,12,\n"
            ."Sari,081200000008,\n"
            ."Tono,081200000010,32/01/1990\n"
            ."Wahyu,,\n";

        $res = $this->api('POST', '/api/v1/customers/import', $this->owner, ['csv' => $csv])->assertUnprocessable();
        $this->assertSame([3, 4, 5, 6, 7], array_column($res->json('data.errors'), 'row'));
        $this->assertSame(0, $this->inShop(fn () => Customer::count()));

        $this->api('POST', '/api/v1/customers/import', $this->owner, ['csv' => "HP\n0812"])
            ->assertUnprocessable()->assertJsonPath('data.errors.0.row', 1);
    }

    public function test_tenant_export_includes_customers(): void
    {
        $this->register(['name' => 'Yuni', 'phone' => '081200000011'])->assertCreated();
        $export = app(TenantDataService::class)->export($this->shop->tenant);
        $this->assertCount(1, $export['tables']['customers']);
    }
}
