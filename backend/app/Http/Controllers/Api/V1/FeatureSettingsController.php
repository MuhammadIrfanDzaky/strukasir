<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Feature;
use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Models\TenantSetting;
use App\Support\Audit;
use App\Support\PhoneNumber;
use App\Support\Tenancy\FeatureGate;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Pengaturan → Fitur (owner): nyalakan/matikan modul untuk kedai ini, dalam batas paket.
 * Disimpan sebagai override di `tenant_features`; tablet menerima hasilnya lewat GET /menu
 * (versi menu ikut berubah, jadi semua tablet memuat ulang otomatis).
 * Mematikan fitur tidak menghapus data apa pun, hanya menyembunyikan/menolak pemakaian baru.
 */
class FeatureSettingsController extends Controller
{
    public function show(FeatureGate $gate, TenantContext $context): JsonResponse
    {
        return response()->json(['data' => $this->present($gate, $context->id())]);
    }

    public function update(Request $request, FeatureGate $gate, TenantContext $context): JsonResponse
    {
        $toggleable = array_map(fn (Feature $f) => $f->value, array_filter(Feature::cases(), fn (Feature $f) => $f->ownerToggleable()));
        $data = $request->validate([
            'features' => ['sometimes', 'array:'.implode(',', $toggleable)],
            'features.*' => ['boolean'],
            'tax_percent' => ['sometimes', 'numeric', 'between:0,100', 'decimal:0,2'],
            'service_percent' => ['sometimes', 'numeric', 'between:0,100', 'decimal:0,2'],
            'tax_inclusive' => ['sometimes', 'boolean'],
            'service_inclusive' => ['sometimes', 'boolean'],
            'customer_phone_required' => ['sometimes', 'boolean'],
            'credit_default_limit' => ['sometimes', 'nullable', 'integer', 'min:0', 'max:1000000000'],
            // Laporan tutup shift ke owner.
            'report_email' => ['sometimes', 'boolean'],
            'report_whatsapp' => ['sometimes', 'nullable', 'string', 'max:30'],
        ]);
        if (isset($data['report_whatsapp']) && trim($data['report_whatsapp']) !== '' && PhoneNumber::normalize($data['report_whatsapp']) === null) {
            throw ValidationException::withMessages(['report_whatsapp' => 'No WhatsApp tidak valid.']);
        }

        $tenantId = $context->id();
        $current = $gate->forTenant($tenantId);
        $available = $this->available($tenantId);
        $wanted = array_map(fn ($v) => (bool) $v, $data['features'] ?? []) + $current;

        foreach ($data['features'] ?? [] as $key => $enabled) {
            if ($enabled && ! in_array($key, $available, true)) {
                throw ValidationException::withMessages(["features.{$key}" => 'Fitur ini tidak termasuk paket Anda.']);
            }
        }
        foreach (Feature::cases() as $feature) {
            $needs = $feature->requires();
            if ($needs !== null && ($wanted[$feature->value] ?? false) && ! ($wanted[$needs->value] ?? false)) {
                throw ValidationException::withMessages([
                    "features.{$feature->value}" => "{$feature->label()} butuh fitur {$needs->label()} aktif.",
                ]);
            }
        }

        // Open Bill yang masih terbuka harus dibayar/di-void dulu, supaya tidak "hilang" dari layar kasir.
        if (($current[Feature::OpenBill->value] ?? false) && ! $wanted[Feature::OpenBill->value]) {
            $open = Order::query()->where('status', 'open')->count();
            if ($open > 0) {
                throw ValidationException::withMessages([
                    'features.open_bill' => "Masih ada {$open} Open Bill belum dibayar. Bayar atau batalkan dulu sebelum mematikan fitur ini.",
                ]);
            }
        }

        $settings = TenantSetting::query()->firstOrFail();
        $before = ['features' => $current, 'tax_bp' => $settings->tax_rate_bp, 'service_bp' => $settings->service_rate_bp,
            'tax_inclusive' => $settings->tax_inclusive, 'service_inclusive' => $settings->service_inclusive,
            'customer_phone_required' => $settings->customer_phone_required, 'credit_default_limit' => $settings->credit_default_limit];

        DB::transaction(function () use ($data, $tenantId, $settings) {
            foreach ($data['features'] ?? [] as $key => $enabled) {
                DB::table('tenant_features')->upsert(
                    [['tenant_id' => $tenantId, 'feature_key' => $key, 'enabled' => (bool) $enabled, 'created_at' => now(), 'updated_at' => now()]],
                    ['tenant_id', 'feature_key'],
                    ['enabled', 'updated_at'],
                );
            }

            // Persen → basis poin; 0 = tidak dipungut.
            foreach (['tax' => 'tax_percent', 'service' => 'service_percent'] as $prefix => $field) {
                if (array_key_exists($field, $data)) {
                    $bp = (int) round(((float) $data[$field]) * 100);
                    $settings->{"{$prefix}_rate_bp"} = $bp;
                    $settings->{"{$prefix}_enabled"} = $bp > 0;
                }
            }
            if (array_key_exists('report_whatsapp', $data)) {
                $settings->report_whatsapp = PhoneNumber::normalize($data['report_whatsapp']);
            }
            if (array_key_exists('report_email', $data)) {
                $settings->report_email = (bool) $data['report_email'];
            }
            if (array_key_exists('credit_default_limit', $data)) {
                $settings->credit_default_limit = $data['credit_default_limit'];
            }
            foreach (['tax_inclusive', 'service_inclusive', 'customer_phone_required'] as $flag) {
                if (array_key_exists($flag, $data)) {
                    $settings->{$flag} = (bool) $data[$flag];
                }
            }
            $settings->save();
        });

        $gate->flush();
        $after = $this->present($gate, $tenantId);
        Audit::record('settings.features_updated', $settings, before: $before, after: [
            'features' => $gate->forTenant($tenantId), 'tax_bp' => $settings->tax_rate_bp, 'service_bp' => $settings->service_rate_bp,
            'tax_inclusive' => $settings->tax_inclusive, 'service_inclusive' => $settings->service_inclusive,
            'customer_phone_required' => $settings->customer_phone_required,
            'credit_default_limit' => $settings->credit_default_limit,
        ]);

        return response()->json(['data' => $after]);
    }

    /** @return list<string> fitur yang termasuk paket kedai */
    private function available(string $tenantId): array
    {
        $planId = DB::table('tenants')->where('id', $tenantId)->value('plan_id');

        return DB::table('plan_features')->where('plan_id', $planId)->pluck('feature_key')->all();
    }

    private function present(FeatureGate $gate, string $tenantId): array
    {
        $enabled = $gate->forTenant($tenantId);
        $available = $this->available($tenantId);
        $settings = TenantSetting::query()->firstOrFail();

        return [
            'features' => collect(Feature::cases())
                ->filter(fn (Feature $f) => $f->ownerToggleable())
                ->map(fn (Feature $f) => [
                    'key' => $f->value,
                    'label' => $f->label(),
                    'description' => $f->description(),
                    'available' => in_array($f->value, $available, true),
                    'enabled' => $enabled[$f->value] ?? false,
                    'requires' => $f->requires()?->value,
                ])->values(),
            'tax_percent' => $settings->tax_rate_bp / 100,
            'service_percent' => $settings->service_rate_bp / 100,
            'tax_inclusive' => (bool) $settings->tax_inclusive,
            'service_inclusive' => (bool) $settings->service_inclusive,
            'customer_phone_required' => (bool) $settings->customer_phone_required,
            'credit_default_limit' => $settings->credit_default_limit === null ? null : (int) $settings->credit_default_limit,
            'report_email' => (bool) $settings->report_email,
            // Kosong = pakai no HP saat daftar.
            'report_whatsapp' => $settings->report_whatsapp,
            'signup_phone' => DB::table('tenants')->where('id', $tenantId)->value('phone'),
        ];
    }
}
