<?php

namespace App\Support\Tenancy;

use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

/**
 * Tenant aktif untuk request/proses saat ini.
 *
 * Satu-satunya sumber tenant: diisi server dari token yang terautentikasi (lihat
 * SetTenantContext), tidak pernah dari parameter yang dikirim klien. Setiap perubahan
 * ikut disetel ke variabel sesi PostgreSQL `app.tenant_id` yang dibaca kebijakan RLS.
 */
class TenantContext
{
    private ?string $tenantId = null;

    private bool $bypassing = false;

    public function id(): ?string
    {
        return $this->tenantId;
    }

    public function has(): bool
    {
        return $this->tenantId !== null;
    }

    public function bypassing(): bool
    {
        return $this->bypassing;
    }

    public function set(?string $tenantId): void
    {
        $this->tenantId = $tenantId;
        DB::select("select set_config('app.tenant_id', ?, false)", [$tenantId ?? '']);
    }

    public function clear(): void
    {
        $this->set(null);
    }

    /**
     * Jalankan callback di dalam konteks tenant tertentu, lalu kembalikan konteks sebelumnya.
     *
     * @template T
     *
     * @param  callable(): T  $callback
     * @return T
     */
    public function run(string $tenantId, callable $callback): mixed
    {
        $previous = $this->tenantId;
        $this->set($tenantId);

        try {
            return $callback();
        } finally {
            $this->restore(fn () => $this->set($previous), fn () => $this->tenantId = $previous);
        }
    }

    /**
     * Pulihkan konteks setelah callback. Jika query di dalam transaksi gagal, transaksi
     * PostgreSQL berstatus aborted dan set_config ikut gagal — jangan sampai itu menutupi
     * error aslinya. Rollback transaksi akan mengembalikan variabel sesi dengan sendirinya.
     */
    private function restore(callable $restoreAll, callable $restorePhpState): void
    {
        try {
            $restoreAll();
        } catch (QueryException $e) {
            $restorePhpState();

            if (DB::transactionLevel() === 0) {
                throw $e;
            }
        }
    }

    /**
     * Akses lintas tenant secara sadar (seeder, offboarding, tugas sistem). Jangan dipakai di
     * jalur request biasa.
     *
     * @template T
     *
     * @param  callable(): T  $callback
     * @return T
     */
    public function bypass(callable $callback): mixed
    {
        $previous = $this->bypassing;
        $this->bypassing = true;
        DB::select("select set_config('app.bypass_rls', 'on', false)");

        try {
            return $callback();
        } finally {
            $this->bypassing = $previous;
            $this->restore(
                fn () => DB::select("select set_config('app.bypass_rls', ?, false)", [$previous ? 'on' : 'off']),
                fn () => null,
            );
        }
    }
}
