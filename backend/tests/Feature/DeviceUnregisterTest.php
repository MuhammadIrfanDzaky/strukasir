<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use Illuminate\Support\Str;
use Tests\TestCase;

/** Owner mengeluarkan tablet yang sedang dipakai dari usahanya. */
class DeviceUnregisterTest extends TestCase
{
    public function test_owner_unregisters_current_tablet_and_all_its_sessions_end(): void
    {
        $shop = $this->makeShop();
        $owner = $this->pinLogin($shop, $shop->owner);
        $cashier = $this->pinLogin($shop);

        $this->api('POST', '/api/v1/devices/current/unregister', $owner)->assertOk();

        $this->api('GET', '/api/v1/auth/staff', $shop->deviceToken)->assertUnauthorized();
        $this->api('GET', '/api/v1/menu', $owner)->assertUnauthorized();
        $this->api('GET', '/api/v1/menu', $cashier)->assertUnauthorized();
        $this->assertNotNull($shop->device->fresh()->revoked_at);
        $this->tenancy()->run($shop->tenant->id, fn () => $this->assertSame(1,
            AuditLog::query()->where('action', 'device.unregistered')->count()));

        // Instalasi baru (install id baru) bisa didaftarkan lagi sebagai tablet baru.
        $this->api('POST', '/api/v1/devices/register', null, [
            'email' => $shop->owner->email, 'password' => self::OWNER_PASSWORD, 'device_id' => (string) Str::uuid(),
        ])->assertCreated()->assertJsonPath('device.code', 'T2');
    }

    public function test_cashier_cannot_unregister_tablet(): void
    {
        $shop = $this->makeShop();

        $this->api('POST', '/api/v1/devices/current/unregister', $this->pinLogin($shop))->assertForbidden();
        $this->assertNull($shop->device->fresh()->revoked_at);
    }

    public function test_other_tablets_keep_working(): void
    {
        $shop = $this->makeShop();
        $second = $this->api('POST', '/api/v1/devices/register', null, [
            'email' => $shop->owner->email, 'password' => self::OWNER_PASSWORD, 'device_id' => (string) Str::uuid(),
        ])->json('token');

        $this->api('POST', '/api/v1/devices/current/unregister', $this->pinLogin($shop, $shop->owner))->assertOk();

        $this->api('GET', '/api/v1/auth/staff', $second)->assertOk();
    }
}
