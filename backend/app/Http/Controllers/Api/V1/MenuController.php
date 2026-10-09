<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Feature;
use App\Enums\Permission;
use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Modifier;
use App\Models\ModifierGroup;
use App\Models\Product;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Support\BusinessTemplate;
use App\Support\Pricing\PricingSettings;
use App\Support\Tenancy\FeatureGate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Snapshot menu lengkap untuk di-cache tablet. `version` berubah setiap ada perubahan menu,
 * sehingga tablet cukup membandingkan versi sebelum mengunduh ulang.
 */
class MenuController extends Controller
{
    public function show(Request $request, FeatureGate $gate): JsonResponse
    {
        // Harga modal = data bisnis owner; kasir tidak menerimanya.
        $withCost = (bool) $request->user()?->can(Permission::MenuManage->value);
        $groups = ModifierGroup::query()->with('modifiers')->orderBy('sort')->orderBy('name')->get();
        $products = Product::query()->orderBy('sort')->orderBy('name')->get();
        $productGroups = DB::table('product_modifier_groups')->orderBy('sort')->get()->groupBy('product_id');
        $settings = TenantSetting::query()->firstOrFail();
        $features = $gate->forTenant($settings->tenant_id);
        $tenant = Tenant::query()->find($settings->tenant_id);
        $pricing = PricingSettings::fromTenant($settings, $features[Feature::TaxService->value] ?? false);

        return response()->json([
            'version' => $this->version(),
            // Untuk menghitung total di tablet; server tetap menghitung ulang (PricingService).
            'pricing' => [
                'service_bp' => $pricing->serviceBp,
                'tax_bp' => $pricing->taxBp,
                'rounding_unit' => $pricing->roundingUnit,
                'service_inclusive' => $pricing->serviceInclusive,
                'tax_inclusive' => $pricing->taxInclusive,
                'cashier_discount_limit_bp' => $settings->cashier_discount_limit_bp,
            ],
            'features' => $features,
            // Label kolom nama di kasir ("meja" hanya untuk usaha makan di tempat).
            'customer_label_hint' => BusinessTemplate::customerLabelHint($tenant?->sector, $tenant?->sales_mode),
            // Form "Pelanggan baru" di kasir: no HP wajib atau boleh kosong (Pengaturan → Fitur).
            'customer_phone_required' => $settings->customer_phone_required,
            // Nama, alamat, penutup & logo struk; disimpan tablet bersama cache menu (struk tetap lengkap saat offline).
            'receipt' => ReceiptSettingsController::present($settings),
            'categories' => Category::query()->orderBy('sort')->orderBy('name')->get()
                ->map(fn (Category $c) => [
                    'id' => $c->id, 'name' => $c->name, 'sort' => $c->sort, 'active' => $c->active,
                ]),
            'products' => $products->map(fn (Product $p) => [
                'id' => $p->id,
                'category_id' => $p->category_id,
                'code' => $p->code,
                'name' => $p->name,
                'price' => $p->price,
                ...($withCost ? ['cost' => $p->cost] : []),
                'favorite' => $p->favorite,
                'active' => $p->active,
                'sold_out' => $p->sold_out,
                'sort' => $p->sort,
                'modifier_group_ids' => ($productGroups[$p->id] ?? collect())->pluck('modifier_group_id')->values(),
            ]),
            'modifier_groups' => $groups->map(fn (ModifierGroup $g) => [
                'id' => $g->id,
                'name' => $g->name,
                'min_select' => $g->min_select,
                'max_select' => $g->max_select,
                'allow_quantity' => $g->allow_quantity,
                'max_quantity' => $g->allow_quantity ? $g->max_quantity : 1,
                'sort' => $g->sort,
                'modifiers' => $g->modifiers->map(fn (Modifier $m) => [
                    'id' => $m->id, 'name' => $m->name, 'price_delta' => $m->price_delta,
                    'active' => $m->active, 'sort' => $m->sort,
                ]),
            ]),
        ]);
    }

    private function version(): string
    {
        $stamps = collect(['categories', 'products', 'modifier_groups', 'modifiers', 'tenant_settings', 'tenant_features'])
            ->map(fn (string $table) => DB::table($table)->selectRaw('count(*) as n, max(updated_at) as t')->first())
            ->map(fn ($row) => $row->n.'@'.$row->t)
            ->implode('|');

        return substr(sha1($stamps), 0, 16);
    }
}
