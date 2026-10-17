<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use Illuminate\Support\Str;
use Tests\TestCase;

/** QRIS statis: gambar milik kedai (owner), tampil di menu tablet; referensi pembayaran tersimpan. */
class QrisSettingsTest extends TestCase
{
    private object $shop;

    private string $owner;

    private string $cashier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
        $this->cashier = $this->pinLogin($this->shop);
    }

    /** PNG grayscale valid tanpa GD. */
    private static function png(int $width, int $height): string
    {
        $chunk = fn (string $type, string $data) => pack('N', strlen($data)).$type.$data.pack('N', crc32($type.$data));
        $raw = str_repeat("\0".str_repeat("\xff", $width), $height);

        return base64_encode("\x89PNG\r\n\x1a\n"
            .$chunk('IHDR', pack('NNCCCCC', $width, $height, 8, 0, 0, 0, 0))
            .$chunk('IDAT', gzcompress($raw))
            .$chunk('IEND', ''));
    }

    public function test_owner_mengunggah_qris_dan_tablet_menerimanya(): void
    {
        $this->api('GET', '/api/v1/menu', $this->cashier)->assertJsonPath('qris', null);
        $this->api('PUT', '/api/v1/settings/qris', $this->cashier, ['image' => self::png(300, 300)])->assertForbidden();
        $this->api('PUT', '/api/v1/settings/qris', $this->owner, ['image' => self::png(60, 60)])
            ->assertUnprocessable()->assertJsonValidationErrors('image'); // terlalu kecil untuk dipindai
        $this->api('PUT', '/api/v1/settings/qris', $this->owner, ['image' => self::png(500, 500)])
            ->assertUnprocessable()->assertJsonValidationErrors('image'); // lebih lebar dari kertas 58 mm
        $this->api('PUT', '/api/v1/settings/qris', $this->owner, ['image' => base64_encode("\xFF\xD8\xFFjpeg")])
            ->assertUnprocessable()->assertJsonValidationErrors('image');

        $image = self::png(320, 360);
        $this->api('PUT', '/api/v1/settings/qris', $this->owner, ['image' => $image, 'print_on_bill' => false])
            ->assertOk()->assertJsonPath('data.print_on_bill', false);
        $this->api('GET', '/api/v1/menu', $this->cashier)->assertJsonPath('qris', ['image' => $image, 'print_on_bill' => false]);

        $this->api('PUT', '/api/v1/settings/qris', $this->owner, ['remove_image' => true])->assertOk();
        $this->api('GET', '/api/v1/menu', $this->cashier)->assertJsonPath('qris', null);
    }

    public function test_referensi_qris_tersimpan_di_order(): void
    {
        $latte = $this->tenancy()->run($this->shop->tenant->id, fn () => Product::create([
            'category_id' => Category::create(['name' => 'Kopi'])->id, 'name' => 'Latte', 'price' => 20000,
        ]));
        $this->api('POST', '/api/v1/shifts/open', $this->cashier, ['opening_cash' => 0])->assertCreated();
        $id = (string) Str::uuid();
        $this->api('PUT', "/api/v1/orders/{$id}", $this->cashier, [
            'items' => [['id' => (string) Str::uuid(), 'product_id' => $latte->id, 'qty' => 1, 'modifier_ids' => []]], 'expected_total' => 20000,
        ])->assertOk();
        $this->api('POST', "/api/v1/orders/{$id}/pay", $this->cashier, [
            'payments' => [['id' => (string) Str::uuid(), 'method' => 'qris', 'amount' => 20000, 'reference' => '4821']], 'expected_total' => 20000,
        ])->assertOk()->assertJsonPath('data.payments.0.reference', '4821');
    }
}
