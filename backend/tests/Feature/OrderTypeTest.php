<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use Illuminate\Support\Str;
use Tests\TestCase;

/** Takeaway / Dine-in per order: service charge hanya dine-in, nomor meja, struk & laporan. */
class OrderTypeTest extends TestCase
{
    private object $shop;

    private string $owner;

    private string $cashier;

    private Product $latte;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->cashier = $this->pinLogin($this->shop);
        $this->latte = $this->tenancy()->run($this->shop->tenant->id, fn () => Product::create([
            'category_id' => Category::create(['name' => 'Kopi'])->id, 'name' => 'Latte', 'price' => 20000,
        ]));
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 0])->assertCreated();
        // Service 10% (tanpa pajak).
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['features' => ['tax_service' => true], 'service_percent' => 10, 'tax_percent' => 0])->assertOk();
    }

    private function save(int $total, array $extra = [], ?string $id = null)
    {
        return $this->api('PUT', '/api/v1/orders/'.($id ?? Str::uuid()), $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => 1, 'modifier_ids' => []]],
            'expected_total' => $total, ...$extra,
        ]);
    }

    public function test_fitur_mati_service_berlaku_seperti_biasa(): void
    {
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['order_types_enabled' => false])->assertOk();
        $this->api('GET', '/api/v1/menu', $this->cashier)->assertJsonPath('order_types.enabled', false);
        $this->save(22000, ['order_type' => 'takeaway', 'table_label' => '5'])->assertOk()
            ->assertJsonPath('data.service_total', 2000)->assertJsonPath('data.order_type', null)->assertJsonPath('data.table_label', null);
    }

    public function test_service_hanya_dine_in_dan_meja_tersimpan(): void
    {
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['order_types_enabled' => true, 'default_order_type' => 'takeaway'])
            ->assertOk()->assertJsonPath('data.order_types_enabled', true)->assertJsonPath('data.default_order_type', 'takeaway');
        $this->api('GET', '/api/v1/menu', $this->cashier)->assertJsonPath('order_types', ['enabled' => true, 'default' => 'takeaway']);

        // Takeaway: tanpa service, meja diabaikan.
        $this->save(20000, ['order_type' => 'takeaway', 'table_label' => '5'])->assertOk()
            ->assertJsonPath('data.service_total', 0)->assertJsonPath('data.order_type', 'takeaway')->assertJsonPath('data.table_label', null);
        // Tanpa jenis = jenis awal kedai.
        $this->save(20000)->assertOk()->assertJsonPath('data.order_type', 'takeaway');
        // Dine-in: service 10% + nomor meja.
        $this->save(22000, ['order_type' => 'dine_in', 'table_label' => ' 12 '])->assertOk()
            ->assertJsonPath('data.service_total', 2000)->assertJsonPath('data.order_type', 'dine_in')->assertJsonPath('data.table_label', '12');
        // Total tablet yang salah menghitung service tetap ditolak.
        $this->save(20000, ['order_type' => 'dine_in'])->assertUnprocessable()->assertJsonValidationErrors('expected_total');
        $this->save(20000, ['order_type' => 'drive_thru'])->assertUnprocessable()->assertJsonValidationErrors('order_type');
    }

    public function test_open_bill_berganti_jenis_dan_laporan_per_jenis(): void
    {
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['order_types_enabled' => true, 'default_order_type' => 'dine_in'])->assertOk();
        $id = (string) Str::uuid();
        $this->save(22000, ['table_label' => '3'], $id)->assertOk()->assertJsonPath('data.order_type', 'dine_in');
        // Pelanggan jadi bawa pulang: service hilang.
        $this->save(20000, ['order_type' => 'takeaway'], $id)->assertOk()->assertJsonPath('data.service_total', 0);
        $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'cash', 'amount' => 20000]], 'expected_total' => 20000,
        ])->assertOk();
        $dine = (string) Str::uuid();
        $this->save(22000, ['table_label' => '7'], $dine)->assertOk();
        $this->api('POST', "/api/v1/orders/{$dine}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'qris', 'amount' => 22000]], 'expected_total' => 22000,
        ])->assertOk();

        $today = now('Asia/Jakarta')->toDateString();
        $this->api('GET', "/api/v1/reports/summary?from={$today}&to={$today}", $this->owner)
            ->assertJsonPath('data.by_order_type.takeaway', ['orders' => 1, 'sales' => 20000])
            ->assertJsonPath('data.by_order_type.dine_in', ['orders' => 1, 'sales' => 22000]);
    }
}
