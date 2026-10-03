<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\Tenant;
use App\Services\TenantDataService;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

/** Kompetensi #19: ekspor & hapus data per kedai tanpa menyentuh kedai lain. */
class TenantDataTest extends TestCase
{
    /** Kedai dengan satu order lunas (ada payments & audit_logs yang append-only). */
    private function shopWithSale(string $name): object
    {
        $shop = $this->makeShop($name);
        $token = $this->pinLogin($shop);
        $product = $this->tenancy()->run($shop->tenant->id, function () {
            $c = Category::create(['name' => 'Kopi']);

            return Product::create(['category_id' => $c->id, 'name' => 'Latte', 'price' => 20000]);
        });

        $this->api('POST', '/api/v1/shifts/open', $token, ['opening_cash' => 0])->assertCreated();
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $token, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $product->id, 'qty' => 1, 'modifier_ids' => []]],
            'expected_total' => 20000,
        ])->assertOk();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $token, [
            'expected_total' => 20000,
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => 20000]],
        ])->assertOk();

        return $shop;
    }

    private function rows(string $tenantId): array
    {
        return $this->tenancy()->bypass(fn () => collect(TenantDataService::TABLES)
            ->mapWithKeys(fn ($t) => [$t => DB::table($t)->where('tenant_id', $tenantId)->count()])
            ->all());
    }

    public function test_export_contains_only_own_data_without_secrets(): void
    {
        $a = $this->shopWithSale('Kedai A');
        $this->shopWithSale('Kedai B');

        $export = app(TenantDataService::class)->export($a->tenant);

        $this->assertSame('Kedai A', $export['tenant']['name']);
        $this->assertCount(1, $export['tables']['orders']);
        $this->assertCount(1, $export['tables']['payments']);
        foreach ($export['tables'] as $rows) {
            foreach ($rows as $row) {
                $this->assertSame($a->tenant->id, $row['tenant_id']);
            }
        }
        $this->assertArrayNotHasKey('pin_hash', $export['tables']['users'][0]);
        $this->assertArrayNotHasKey('password', $export['tables']['users'][0]);
    }

    public function test_export_command_writes_file(): void
    {
        Storage::fake('local');
        $a = $this->shopWithSale('Kedai A');

        $this->assertSame(0, Artisan::call('pos:export-tenant', ['code' => $a->tenant->code]));

        $files = Storage::disk('local')->files('exports');
        $this->assertCount(1, $files);
        $this->assertStringNotContainsString('pin_hash', Storage::disk('local')->get($files[0]));
    }

    public function test_delete_requires_typed_confirmation(): void
    {
        $a = $this->shopWithSale('Kedai A');

        $this->assertSame(1, Artisan::call('pos:delete-tenant', ['code' => $a->tenant->code]));
        $this->assertSame(1, Artisan::call('pos:delete-tenant', ['code' => $a->tenant->code, '--confirm' => 'salah']));
        $this->assertTrue(Tenant::whereKey($a->tenant->id)->exists());
    }

    public function test_delete_removes_one_tenant_completely_and_leaves_others(): void
    {
        $a = $this->shopWithSale('Kedai A');
        $b = $this->shopWithSale('Kedai B');
        $before = $this->rows($b->tenant->id);

        $this->assertSame(0, Artisan::call('pos:delete-tenant', ['code' => $a->tenant->code, '--confirm' => $a->tenant->code]));

        $this->assertFalse(Tenant::whereKey($a->tenant->id)->exists());
        $this->assertSame(0, array_sum($this->rows($a->tenant->id)), 'semua data kedai A (termasuk payments & audit) terhapus');
        $this->assertSame($before, $this->rows($b->tenant->id), 'kedai B tidak tersentuh');
        $this->assertSame(0, DB::table('personal_access_tokens')->whereIn('tokenable_id', [$a->owner->id, $a->cashier->id, $a->device->id])->count());
    }
}
