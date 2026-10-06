<?php

namespace Tests\Feature;

use App\Models\TenantSetting;
use Tests\TestCase;

/** Pengaturan struk & logo per kedai (SEC-27: hanya PNG kecil, dicek dari isinya). */
class ReceiptSettingsTest extends TestCase
{
    private object $shop;

    private string $ownerToken;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('Kedai A');
        $this->ownerToken = $this->pinLogin($this->shop, $this->shop->owner);
    }

    /** PNG grayscale valid tanpa GD: IHDR + IDAT (zlib) + IEND. */
    private static function png(int $width, int $height): string
    {
        $chunk = fn (string $type, string $data) => pack('N', strlen($data)).$type.$data.pack('N', crc32($type.$data));
        $raw = str_repeat("\0".str_repeat("\xff", $width), $height);

        return "\x89PNG\r\n\x1a\n"
            .$chunk('IHDR', pack('NNCCCCC', $width, $height, 8, 0, 0, 0, 0))
            .$chunk('IDAT', gzcompress($raw))
            .$chunk('IEND', '');
    }

    private function update(array $data, ?string $token = null)
    {
        return $this->api('PUT', '/api/v1/settings/receipt', $token ?? $this->ownerToken, $data + ['name' => 'BERRYBREW KOPI']);
    }

    public function test_owner_sets_text_and_logo_and_tablets_receive_it_in_the_menu(): void
    {
        $logo = base64_encode(self::png(300, 120));

        $this->update([
            'header' => "Jl Garu 2 A No. 5 C Harjosari 1\r\nMedan Amplas",
            'footer' => 'Terima Kasih atas Kunjungan Anda',
            'logo' => $logo,
        ])->assertOk()->assertJsonPath('data.header', "Jl Garu 2 A No. 5 C Harjosari 1\nMedan Amplas");

        $this->api('GET', '/api/v1/menu', $this->ownerToken)
            ->assertOk()
            ->assertJsonPath('receipt.name', 'BERRYBREW KOPI')
            ->assertJsonPath('receipt.footer', 'Terima Kasih atas Kunjungan Anda')
            ->assertJsonPath('receipt.logo', $logo);
    }

    public function test_text_only_update_keeps_logo_and_remove_logo_clears_it(): void
    {
        $logo = base64_encode(self::png(64, 64));
        $this->update(['logo' => $logo])->assertOk();

        $this->update(['footer' => 'Sampai jumpa'])->assertOk()->assertJsonPath('data.logo', $logo);
        $this->update(['remove_logo' => true])->assertOk()->assertJsonPath('data.logo', null);
    }

    public function test_cashier_cannot_change_receipt_settings(): void
    {
        $this->update([], $this->pinLogin($this->shop))->assertForbidden();
    }

    public function test_only_small_png_is_accepted(): void
    {
        $jpeg = base64_encode("\xFF\xD8\xFF\xE0".str_repeat('x', 100));
        $svg = base64_encode('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');
        $fakePng = base64_encode("\x89PNG\r\n\x1a\n".'bukan gambar');

        foreach ([$jpeg, $svg, $fakePng, 'bukan-base64!!', base64_encode(self::png(600, 100)), base64_encode(self::png(100, 900))] as $bad) {
            $this->update(['logo' => $bad])->assertUnprocessable()->assertJsonValidationErrors('logo');
        }
        $this->assertNull($this->tenancy()->run($this->shop->tenant->id, fn () => TenantSetting::query()->value('receipt_logo')));
    }

    public function test_other_shops_are_not_affected(): void
    {
        $other = $this->makeShop('Kedai B');
        $this->update(['logo' => base64_encode(self::png(64, 64))])->assertOk();

        $this->api('GET', '/api/v1/menu', $this->pinLogin($other, $other->owner))
            ->assertOk()
            ->assertJsonPath('receipt.name', 'Kedai B')
            ->assertJsonPath('receipt.logo', null);
    }
}
