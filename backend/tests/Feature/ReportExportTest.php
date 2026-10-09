<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use Illuminate\Support\Str;
use Tests\TestCase;

class ReportExportTest extends TestCase
{
    private object $shop;

    private string $cashier;

    private string $owner;

    private Product $latte;

    private string $today;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->cashier = $this->pinLogin($this->shop);
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->latte = $this->tenancy()->run($this->shop->tenant->id, function () {
            $c = Category::create(['name' => 'Kopi']);

            return Product::create(['category_id' => $c->id, 'name' => 'Latte', 'price' => 20000, 'cost' => 8000]);
        });
        $this->today = now($this->shop->tenant->timezone)->toDateString();
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 100000])->assertCreated();
    }

    private function sell(string $label = 'Meja 3'): string
    {
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => 2, 'modifier_ids' => []]],
            'expected_total' => 40000, 'customer_label' => $label,
        ])->assertOk();

        return $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'qris', 'amount' => 40000]], 'expected_total' => 40000,
        ])->assertOk()->json('data.number');
    }

    private function link(string $type, ?string $token = null)
    {
        return $this->api('POST', '/api/v1/reports/export-link', $token ?? $this->owner, ['type' => $type, 'from' => $this->today, 'to' => $this->today]);
    }

    /** Buka tautan seperti browser (tanpa token). */
    private function open(string $url)
    {
        $this->app['auth']->forgetGuards();
        $this->tenancy()->clear();
        $parts = parse_url($url);

        return $this->get($parts['path'].'?'.$parts['query']);
    }

    private function csv(string $type): string
    {
        $res = $this->open($this->link($type)->assertOk()->json('data.url'))->assertOk();
        $this->assertStringStartsWith('text/csv', $res->headers->get('Content-Type'));

        return $res->streamedContent();
    }

    public function test_orders_items_tax_and_cash_exports(): void
    {
        $number = $this->sell();
        $this->api('POST', '/api/v1/shifts/current/cash-movements', $this->cashier, [
            'id' => (string) Str::uuid(), 'kind' => 'out', 'category' => 'ingredients', 'amount' => 15000, 'note' => 'Es batu',
        ])->assertCreated();

        $orders = $this->csv('orders');
        $this->assertStringStartsWith("\xEF\xBB\xBF".'Tanggal;Jam;"No. order"', $orders);
        $this->assertStringContainsString("{$this->today};", $orders);
        $this->assertStringContainsString(";{$number};Lunas;Kasir;\"Meja 3\";;40000;0;0;0;0;40000;0;0;40000;0", $orders);

        $this->assertStringContainsString(';Latte;Kopi;;2;20000;0;40000;16000', $this->csv('items'));
        $this->assertStringContainsString("{$this->today};1;40000;0;0;40000", $this->csv('tax'));
        $this->assertStringContainsString(';Keluar;"Belanja bahan";15000;"Es batu";Kasir;', $this->csv('cash'));
    }

    public function test_formula_injection_is_neutralised(): void
    {
        $this->sell('=HYPERLINK("http://jahat")');
        $this->assertStringContainsString("'=HYPERLINK", $this->csv('orders'));
    }

    public function test_link_is_owner_only_signed_and_short_lived(): void
    {
        $this->link('orders', $this->cashier)->assertForbidden();
        $url = $this->link('orders')->json('data.url');
        $this->assertStringStartsWith('http://localhost/api/v1/exports/reports?', $url);

        $this->open(str_replace('type=orders', 'type=items', $url))->assertForbidden(); // diubah = ditolak
        $this->travel(11)->minutes();
        $this->open($url)->assertForbidden();
    }

    public function test_deactivated_user_cannot_use_old_link(): void
    {
        $url = $this->link('orders')->json('data.url');
        $this->tenancy()->run($this->shop->tenant->id, fn () => User::whereKey($this->shop->owner->id)->update(['active' => false]));
        $this->open($url)->assertForbidden();
    }

    public function test_export_contains_only_own_shop(): void
    {
        $this->sell('Rahasia kedai A');
        $other = $this->makeShop('Lain');
        $otherOwner = $this->pinLogin($other, $other->owner);
        $url = $this->api('POST', '/api/v1/reports/export-link', $otherOwner, ['type' => 'orders', 'from' => $this->today, 'to' => $this->today])
            ->json('data.url');
        $this->assertStringNotContainsString('Rahasia', $this->open($url)->assertOk()->streamedContent());
    }
}
