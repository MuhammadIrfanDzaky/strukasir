<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Feature;
use App\Enums\Permission;
use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Modifier;
use App\Models\ModifierGroup;
use App\Models\Outlet;
use App\Models\Product;
use App\Models\Promotion;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Services\InventoryService;
use App\Services\LoyaltyService;
use App\Services\PromotionService;
use App\Services\TierService;
use App\Support\BusinessTemplate;
use App\Support\PlanCatalog;
use App\Support\Pricing\PricingSettings;
use App\Support\Tenancy\FeatureGate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
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
        // HPP dari resep (owner, fitur stok): ditampilkan di form produk menggantikan modal manual.
        $device = $request->attributes->get('device');
        $recipeCosts = $withCost && $device && app(InventoryService::class)->enabled() ? app(InventoryService::class)->productCosts($device->outlet_id) : [];
        $outlet = $device ? Outlet::query()->find($device->outlet_id) : null;
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
            // Fitur di luar paket (tampil terkunci + ajakan upgrade untuk owner); fitur yang dimatikan owner tidak termasuk.
            'locked_features' => PlanCatalog::lockedFeatures($tenant?->plan?->code),
            // Label kolom nama di kasir ("meja" hanya untuk usaha makan di tempat).
            'customer_label_hint' => BusinessTemplate::customerLabelHint($tenant?->sector, $tenant?->sales_mode, (bool) $settings->order_types_enabled),
            // Pilihan Takeaway | Dine-in di kasir; service charge hanya untuk dine-in bila aktif.
            'order_types' => ['enabled' => (bool) $settings->order_types_enabled, 'default' => $settings->default_order_type],
            // Form "Pelanggan baru" di kasir: no HP wajib atau boleh kosong (Pengaturan → Fitur).
            'customer_phone_required' => $settings->customer_phone_required,
            // Program loyalitas + hadiah aktif (null bila tidak berjalan): kasir menukar hadiah & melihat
            // perkiraan stempel/poin; server tetap menghitung ulang saat simpan & bayar.
            'loyalty' => app(LoyaltyService::class)->presentForMenu(),
            // Jam server & selisih zona waktu kedai: tablet menilai jadwal promo dengan jam kedai,
            // bukan jam/zona tablet (jam tablet yang meleset tidak membuat total berbeda dengan server).
            'clock' => ['now' => now()->toIso8601String(), 'utc_offset' => Carbon::now($tenant?->timezone ?: 'Asia/Jakarta')->utcOffset()],
            // Promo otomatis aktif + jadwalnya (kosong = fitur mati); tablet menghitung, server memeriksa ulang.
            'promotions' => app(PromotionService::class)->enabled()
                ? Promotion::query()->where('active', true)->orderBy('name')->get()->map(fn ($p) => PromotionService::presentPromotion($p))->values() : [],
            // Tingkat member aktif (kosong = fitur mati): untuk lencana & pengali di tablet.
            'member_tiers' => app(TierService::class)->enabled()
                ? app(TierService::class)->tiers()->map(fn ($t) => TierService::present($t))->values() : [],
            // Nama, alamat, penutup & logo struk; disimpan tablet bersama cache menu (struk tetap lengkap saat offline).
            'receipt' => ReceiptSettingsController::present($settings),
            // QRIS statis kedai (ditampilkan ke pembeli saat bayar QRIS); null = belum diunggah.
            'qris' => QrisSettingsController::present($settings),
            // Outlet tablet ini (nama & alamat di struk); `outlets` = jumlah outlet aktif (nama outlet tampil bila > 1).
            'outlet' => $outlet?->present(),
            'outlet_count' => Outlet::query()->where('active', true)->count(),
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
                ...($withCost ? ['cost' => $p->cost, 'recipe_cost' => $recipeCosts[$p->id] ?? null] : []),
                'favorite' => $p->favorite,
                'active' => $p->active,
                'sold_out' => $p->sold_out,
                'sort' => $p->sort,
                'modifier_group_ids' => ($productGroups[$p->id] ?? collect())->pluck('modifier_group_id')->values(),
            ]),
            'modifier_groups' => $groups->map(fn (ModifierGroup $g) => [
                'id' => $g->id,
                'name' => $g->name,
                'category_ids' => $g->category_ids ?? [],
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
        $stamps = collect(['outlets', 'categories', 'products', 'modifier_groups', 'modifiers', 'tenant_settings', 'tenant_features', 'loyalty_programs', 'loyalty_rewards', 'member_tiers', 'promotions', 'ingredients', 'recipe_items'])
            ->map(fn (string $table) => DB::table($table)->selectRaw('count(*) as n, max(updated_at) as t')->first())
            ->map(fn ($row) => $row->n.'@'.$row->t)
            ->implode('|');

        return substr(sha1($stamps), 0, 16);
    }
}
