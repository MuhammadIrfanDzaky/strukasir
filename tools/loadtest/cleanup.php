<?php
// Hapus semua kedai uji (kode "lt-*") beserta datanya. Wajib dijalankan setelah load test di produksi.
require '/app/vendor/autoload.php';
$app = require '/app/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\Tenant;
use App\Services\TenantDataService;

$count = 0;
foreach (Tenant::where('code', 'like', 'lt-%')->get() as $tenant) {
    app(TenantDataService::class)->purge($tenant);
    $count++;
}
echo "Dihapus: $count kedai uji\n";
