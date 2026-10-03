<?php

namespace App\Console\Commands;

use App\Models\Tenant;
use App\Services\TenantDataService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;

/** Ekspor seluruh data satu kedai ke JSON (mis. diserahkan saat klien berhenti berlangganan). */
class ExportTenant extends Command
{
    protected $signature = 'pos:export-tenant {code : Kode kedai}';

    protected $description = 'Ekspor semua data satu kedai ke file JSON (tanpa password/PIN/token)';

    public function handle(TenantDataService $data): int
    {
        $tenant = Tenant::where('code', $this->argument('code'))->first();
        if ($tenant === null) {
            $this->error('Kedai tidak ditemukan.');

            return self::FAILURE;
        }

        $export = $data->export($tenant);
        $path = 'exports/'.$tenant->code.'-'.now()->format('Ymd-His').'.json';
        Storage::disk('local')->put($path, json_encode($export, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));

        foreach ($export['tables'] as $table => $rows) {
            $this->line(sprintf('  %-24s %d', $table, count($rows)));
        }
        $this->info('Tersimpan: '.Storage::disk('local')->path($path));

        return self::SUCCESS;
    }
}
