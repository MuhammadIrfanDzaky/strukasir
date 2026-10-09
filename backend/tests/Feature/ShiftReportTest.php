<?php

namespace Tests\Feature;

use App\Mail\ShiftReportMail;
use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Tests\TestCase;

class ShiftReportTest extends TestCase
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
        $this->latte = $this->tenancy()->run($this->shop->tenant->id, function () {
            User::whereKey($this->shop->owner->id)->update(['email' => 'owner@berrybrew.test', 'email_verified_at' => now()]);
            $c = Category::create(['name' => 'Kopi']);

            return Product::create(['category_id' => $c->id, 'name' => 'Kopi Susu Aren', 'price' => 20000]);
        });
        DB::table('tenants')->where('id', $this->shop->tenant->id)->update(['phone' => '+6281299998888']);
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 100000])->assertCreated();
    }

    private function sell(int $qty, string $method): void
    {
        $id = (string) Str::uuid();
        $total = 20000 * $qty;
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $this->latte->id, 'qty' => $qty, 'modifier_ids' => []]],
            'expected_total' => $total,
        ])->assertOk();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => $method, 'amount' => $total, ...($method === 'cash' ? ['tendered' => $total] : [])]],
            'expected_total' => $total,
        ])->assertOk();
    }

    private function closeShift(int $counted)
    {
        return $this->api('POST', '/api/v1/shifts/close', $this->cashier, ['counted_cash' => $counted, 'note' => 'Hujan deras'])->assertOk();
    }

    public function test_closing_shift_emails_owner_and_report_text_is_complete(): void
    {
        Mail::fake();
        $this->sell(2, 'cash');
        $this->sell(1, 'qris');
        $this->api('POST', '/api/v1/shifts/current/cash-movements', $this->cashier, [
            'id' => (string) Str::uuid(), 'kind' => 'out', 'category' => 'ingredients', 'amount' => 10000,
        ])->assertCreated();
        $shiftId = $this->closeShift(125000)->json('data.id'); // seharusnya 130.000 → kurang 5.000

        Mail::assertSent(ShiftReportMail::class, fn (ShiftReportMail $m) => $m->hasTo('owner@berrybrew.test')
            && str_contains($m->body, 'Penjualan: Rp60.000'));

        $res = $this->api('GET', "/api/v1/shifts/{$shiftId}/report", $this->cashier)->assertOk();
        $text = $res->json('data.text');
        foreach (['*Laporan shift BerryBrew*', '*Penjualan: Rp60.000* (2 transaksi)', 'Tunai Rp40.000 · QRIS Rp20.000',
            'Kas keluar Rp10.000', 'KURANG Rp5.000', 'Terlaris: Kopi Susu Aren 3×', 'Catatan: Hujan deras',
            'Total hari ini (semua tablet): Rp60.000 · 2 transaksi'] as $part) {
            $this->assertStringContainsString($part, $text);
        }
        $this->assertStringStartsWith('https://wa.me/6281299998888?text=', $res->json('data.whatsapp_url'));
    }

    public function test_owner_sets_whatsapp_number_and_can_turn_email_off(): void
    {
        Mail::fake();
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['report_email' => false, 'report_whatsapp' => '0812-1111-2222'])
            ->assertOk()->assertJsonPath('data.report_whatsapp', '+6281211112222')->assertJsonPath('data.report_email', false);
        $this->api('PUT', '/api/v1/settings/features', $this->owner, ['report_whatsapp' => 'abc'])->assertUnprocessable();

        $shiftId = $this->closeShift(100000)->json('data.id');
        Mail::assertNothingSent();
        $this->assertStringStartsWith('https://wa.me/6281211112222?', $this->api('GET', "/api/v1/shifts/{$shiftId}/report", $this->owner)->json('data.whatsapp_url'));
    }

    public function test_no_email_without_verified_owner_email_and_no_link_without_number(): void
    {
        Mail::fake();
        $this->tenancy()->run($this->shop->tenant->id, fn () => User::whereKey($this->shop->owner->id)->update(['email_verified_at' => null]));
        DB::table('tenants')->where('id', $this->shop->tenant->id)->update(['phone' => null]);
        $shiftId = $this->closeShift(100000)->json('data.id');
        Mail::assertNothingSent();
        $this->api('GET', "/api/v1/shifts/{$shiftId}/report", $this->cashier)->assertJsonPath('data.whatsapp_url', null);
    }

    public function test_report_of_another_shop_is_not_found(): void
    {
        $shiftId = $this->closeShift(100000)->json('data.id');
        $other = $this->makeShop('Lain');
        $this->api('GET', "/api/v1/shifts/{$shiftId}/report", $this->pinLogin($other))->assertNotFound();
    }
}
