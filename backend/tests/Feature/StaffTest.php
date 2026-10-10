<?php

namespace Tests\Feature;

use App\Models\User;
use Tests\TestCase;

class StaffTest extends TestCase
{
    private object $shop;

    private string $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->shop = $this->makeShop('BerryBrew');
        $this->owner = $this->pinLogin($this->shop, $this->shop->owner);
    }

    private function add(string $name, string $pin = '481526')
    {
        return $this->api('POST', '/api/v1/staff', $this->owner, ['name' => $name, 'pin' => $pin]);
    }

    private function login(string $userId, string $pin)
    {
        return $this->api('POST', '/api/v1/auth/pin', $this->shop->deviceToken, ['user_id' => $userId, 'pin' => $pin]);
    }

    public function test_owner_menambah_kasir_yang_langsung_bisa_login(): void
    {
        $id = $this->add('  Sari   Dewi ')->assertCreated()
            ->assertJsonPath('data.name', 'Sari Dewi')->assertJsonPath('data.role', 'cashier')->json('data.id');

        $this->assertContains('Sari Dewi', array_column($this->api('GET', '/api/v1/auth/staff', $this->shop->deviceToken)->json('data'), 'name'));
        $token = $this->login($id, '481526')->assertOk()->json('token');
        $this->api('GET', '/api/v1/auth/me', $token)->assertOk();

        $list = $this->api('GET', '/api/v1/staff', $this->owner)->assertOk()->json('data');
        $this->assertSame(['Owner', 'Kasir', 'Sari Dewi'], array_column($list, 'name'));
    }

    public function test_validasi_nama_unik_dan_pin_kuat(): void
    {
        $this->add('Kasir')->assertUnprocessable()->assertJsonValidationErrors('name'); // sudah ada
        $this->add('Owner')->assertUnprocessable()->assertJsonValidationErrors('name');
        $this->add('Budi', '123456')->assertUnprocessable()->assertJsonValidationErrors('pin');
        $this->add('Budi', '111111')->assertUnprocessable()->assertJsonValidationErrors('pin');
        $this->add('Budi', '12345')->assertUnprocessable()->assertJsonValidationErrors('pin');
        $this->add('<script>')->assertUnprocessable()->assertJsonValidationErrors('name');
    }

    public function test_hanya_owner(): void
    {
        $cashier = $this->pinLogin($this->shop);
        $this->api('GET', '/api/v1/staff', $cashier)->assertForbidden();
        $this->api('POST', '/api/v1/staff', $cashier, ['name' => 'Budi', 'pin' => '481526'])->assertForbidden();
    }

    public function test_nonaktif_keluar_dari_tablet_dan_tidak_bisa_login(): void
    {
        $cashierId = $this->shop->cashier->id;
        $token = $this->pinLogin($this->shop);

        $this->api('PUT', "/api/v1/staff/{$cashierId}", $this->owner, ['name' => 'Kasir', 'active' => false])
            ->assertOk()->assertJsonPath('data.active', false);
        $this->api('GET', '/api/v1/auth/me', $token)->assertUnauthorized();
        $this->login($cashierId, self::PIN)->assertUnprocessable();
        $this->assertNotContains('Kasir', array_column($this->api('GET', '/api/v1/auth/staff', $this->shop->deviceToken)->json('data'), 'name'));

        $this->api('PUT', "/api/v1/staff/{$cashierId}", $this->owner, ['name' => 'Kasir Pagi', 'active' => true])->assertOk();
        $this->login($cashierId, self::PIN)->assertOk();
    }

    public function test_reset_pin_membuka_kunci_dan_mengganti_pin(): void
    {
        $cashierId = $this->shop->cashier->id;
        $old = $this->pinLogin($this->shop);
        for ($i = 0; $i < User::MAX_FAILED_ATTEMPTS; $i++) {
            $this->login($cashierId, '000000');
        }
        $this->assertTrue(collect($this->api('GET', '/api/v1/staff', $this->owner)->json('data'))->firstWhere('id', $cashierId)['locked']);

        $this->api('POST', "/api/v1/staff/{$cashierId}/pin", $this->owner, ['pin' => '730914'])->assertOk()->assertJsonPath('data.locked', false);
        $this->api('GET', '/api/v1/auth/me', $old)->assertUnauthorized();
        $this->login($cashierId, self::PIN)->assertUnprocessable();
        $this->login($cashierId, '730914')->assertOk();
    }

    public function test_akun_owner_tidak_diubah_dari_sini(): void
    {
        $ownerId = $this->shop->owner->id;
        $this->api('PUT', "/api/v1/staff/{$ownerId}", $this->owner, ['name' => 'X', 'active' => false])->assertForbidden();
        $this->api('POST', "/api/v1/staff/{$ownerId}/pin", $this->owner, ['pin' => '730914'])->assertForbidden();
    }

    public function test_pegawai_kedai_lain_tidak_terlihat(): void
    {
        $other = $this->makeShop('Lain');
        $this->api('PUT', "/api/v1/staff/{$other->cashier->id}", $this->owner, ['name' => 'Curian'])->assertNotFound();
        $this->assertNotContains($other->cashier->id, array_column($this->api('GET', '/api/v1/staff', $this->owner)->json('data'), 'id'));
    }
}
