<?php

namespace App\Services;

use App\Models\Device;
use App\Models\Tenant;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * Siklus hidup data per kedai (kompetensi #19): ekspor untuk diserahkan ke klien, dan penghapusan
 * total saat berhenti berlangganan — tanpa menyentuh kedai lain.
 */
class TenantDataService
{
    /** Tabel milik tenant (semua punya kolom tenant_id), urut dari induk ke anak. */
    public const TABLES = [
        'tenant_settings', 'tenant_features', 'users', 'devices', 'member_tiers', 'customers',
        'categories', 'modifier_groups', 'modifiers', 'products', 'product_modifier_groups', 'loyalty_programs', 'loyalty_rewards',
        'shifts', 'order_counters', 'orders', 'order_items', 'order_item_modifiers', 'payments', 'loyalty_entries', 'credit_repayments', 'message_templates', 'message_logs',
        'audit_logs',
    ];

    /** Kolom rahasia yang tidak pernah ikut diekspor. */
    private const HIDDEN = ['users' => ['password', 'pin_hash', 'remember_token', 'two_factor_secret', 'two_factor_last_step']];

    public function __construct(private readonly TenantContext $context) {}

    /** @return array<string, mixed> */
    public function export(Tenant $tenant): array
    {
        return $this->context->run($tenant->id, function () use ($tenant) {
            $data = [
                'format' => 'berrybrew-pos-export/1',
                'exported_at' => now()->toIso8601String(),
                'tenant' => $tenant->only(['id', 'code', 'name', 'timezone', 'created_at']),
            ];

            foreach (self::TABLES as $table) {
                $rows = DB::table($table)->where('tenant_id', $tenant->id)->get();
                $hidden = self::HIDDEN[$table] ?? [];
                $data['tables'][$table] = $rows
                    ->map(fn ($row) => collect((array) $row)->except($hidden)->all())
                    ->all();
            }

            return $data;
        });
    }

    /**
     * Hapus kedai beserta seluruh datanya. Pengaman append-only (payments, audit_logs) dibuka
     * hanya di dalam transaksi ini lewat `app.allow_purge` (SET LOCAL), lalu tertutup otomatis.
     *
     * @return array<string, int> jumlah baris per tabel sebelum dihapus
     */
    public function purge(Tenant $tenant): array
    {
        return DB::transaction(function () use ($tenant) {
            DB::select("select set_config('app.allow_purge', 'on', true)");

            return $this->context->run($tenant->id, function () use ($tenant) {
                $counts = [];
                foreach (self::TABLES as $table) {
                    $counts[$table] = DB::table($table)->where('tenant_id', $tenant->id)->count();
                }

                // Token tidak punya FK ke tenant (polymorphic) → hapus eksplisit.
                DB::table('personal_access_tokens')
                    ->where(fn ($q) => $q
                        ->where('tokenable_type', (new User)->getMorphClass())
                        ->whereIn('tokenable_id', DB::table('users')->where('tenant_id', $tenant->id)->select('id')))
                    ->orWhere(fn ($q) => $q
                        ->where('tokenable_type', (new Device)->getMorphClass())
                        ->whereIn('tokenable_id', DB::table('devices')->where('tenant_id', $tenant->id)->select('id')))
                    ->delete();

                // Semua tabel tenant ikut terhapus lewat ON DELETE CASCADE.
                DB::table('tenants')->where('id', $tenant->id)->delete();

                // audit_logs kedai ikut terhapus, jadi jejak penghapusan dicatat di log server.
                Log::warning('tenant.purged', ['tenant_id' => $tenant->id, 'code' => $tenant->code, 'rows' => $counts]);

                return $counts;
            });
        });
    }
}
