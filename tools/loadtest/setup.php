<?php
// Membuat N kedai uji lengkap (kasir, tablet, token, shift terbuka, 5 produk) lalu menulis tokens.json.
require '/app/vendor/autoload.php';
$app = require '/app/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Enums\Role;
use App\Models\{Category, Device, Product, User};
use App\Services\{ShiftService, TenantProvisioner};
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Str;

$n = (int) ($argv[1] ?? 100);
Artisan::call('db:seed', ['--class' => Database\Seeders\FeatureSeeder::class, '--force' => true]);
$ctx = app(TenantContext::class);
$out = [];

for ($i = 1; $i <= $n; $i++) {
    $tenant = app(TenantProvisioner::class)->create("lt-$i", "Kedai Uji $i", 'Owner', "owner$i@loadtest.test", Str::password(16, symbols: false), '123456');
    $out[] = $ctx->run($tenant->id, function () {
        $cashier = new User(['name' => 'Kasir']);
        $cashier->role = Role::Cashier;
        $cashier->setPin('123456');
        $cashier->save();

        $device = new Device(['name' => 'Tablet']);
        $device->code = 'T1';
        $device->save();

        $token = $cashier->createToken('lt', ['user'], now()->addDay());
        $token->accessToken->forceFill(['device_id' => $device->id])->save();
        app(ShiftService::class)->open($device, $cashier, 100000);

        $cat = Category::create(['name' => 'Kopi']);
        $products = [];
        foreach ([13000, 15000, 18000, 20000, 22000] as $k => $price) {
            $p = Product::create(['category_id' => $cat->id, 'name' => "Produk $k", 'price' => $price]);
            $products[] = ['id' => $p->id, 'price' => $price];
        }

        return ['token' => $token->plainTextToken, 'products' => $products];
    });
}

file_put_contents('/tmp/tokens.json', json_encode($out));
echo "OK $n kedai\n";
