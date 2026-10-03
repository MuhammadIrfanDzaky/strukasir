<?php

namespace App\Console\Commands;

use App\Models\Tenant;
use App\Services\TenantDataService;
use Illuminate\Console\Command;

/**
 * Hapus kedai beserta SELURUH datanya (offboarding). Tidak bisa dibatalkan — data hanya bisa
 * kembali dari backup selama masa retensi. Ekspor dulu dengan pos:export-tenant.
 */
class DeleteTenant extends Command
{
    protected $signature = 'pos:delete-tenant {code : Kode kedai} {--confirm= : Ketik ulang kode kedai untuk konfirmasi}';

    protected $description = 'Hapus kedai beserta seluruh datanya (offboarding, permanen)';

    public function handle(TenantDataService $data): int
    {
        $code = $this->argument('code');
        $tenant = Tenant::where('code', $code)->first();
        if ($tenant === null) {
            $this->error('Kedai tidak ditemukan.');

            return self::FAILURE;
        }

        if ($this->option('confirm') !== $code) {
            $this->error("Penghapusan permanen. Ulangi dengan --confirm={$code} setelah data diekspor.");

            return self::FAILURE;
        }

        $counts = $data->purge($tenant);
        $this->info("Kedai '{$tenant->name}' dihapus. Baris terhapus: ".array_sum($counts).'.');

        return self::SUCCESS;
    }
}
