<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Ingredient;
use App\Models\Outlet;
use App\Services\InventoryService;
use App\Support\Audit;
use App\Support\OutletFilter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Stok bahan & resep (fitur `inventory`, izin inventory.manage = owner). Bahan tidak dihapus
 * (riwayat stok merujuknya); gunakan `active=false`.
 */
class InventoryController extends Controller
{
    private const QTY = ['required', 'numeric', 'gt:0', 'max:100000000'];

    public function __construct(private readonly InventoryService $inventory) {}

    /** Stok satu outlet (`?outlet=`, default outlet tablet ini); bahan & resep sama untuk semua outlet. */
    public function index(Request $request): JsonResponse
    {
        $this->guard();
        $outlet = $this->outlet($request);
        $items = $this->inventory->ingredients($outlet)->map(fn (Ingredient $i) => InventoryService::present($i));
        $used = DB::table('recipe_items')->groupBy('ingredient_id')->selectRaw('ingredient_id, count(*) as n')->pluck('n', 'ingredient_id');

        return response()->json(['data' => [
            'ingredients' => $items->map(fn ($i) => [...$i, 'used_in' => (int) ($used[$i['id']] ?? 0)])->values(),
            'recipes' => $this->inventory->recipes(),
            'product_costs' => (object) $this->inventory->productCosts($outlet),
            'outlet_id' => $outlet,
            'summary' => [
                'value' => $items->where('active', true)->sum('value'),
                'low' => $items->where('low', true)->count(),
            ],
        ]]);
    }

    public function saveIngredient(Request $request, ?Ingredient $ingredient = null): JsonResponse
    {
        $this->guard();
        $request->merge(['name' => trim((string) $request->input('name'))]);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:60',
                Rule::unique('ingredients', 'name')->where('tenant_id', $request->user()->tenant_id)->ignore($ingredient?->id)],
            'unit' => ['required', Rule::in(InventoryService::UNITS)],
            'min_stock' => ['nullable', 'numeric', 'min:0', 'max:100000000'],
            'active' => ['sometimes', 'boolean'],
        ], ['name.unique' => 'Nama bahan sudah dipakai.']);

        if ($ingredient?->exists && $ingredient->unit !== $data['unit']
            && DB::table('stock_movements')->where('ingredient_id', $ingredient->id)->exists()) {
            throw ValidationException::withMessages(['unit' => 'Satuan tidak bisa diubah setelah ada riwayat stok.']);
        }

        $before = $ingredient?->exists ? InventoryService::present(Ingredient::query()->withStock($this->outlet($request))->findOrFail($ingredient->id)) : null;
        $ingredient ??= new Ingredient;
        $ingredient->fill([
            ...$data,
            'min_stock' => isset($data['min_stock']) ? round((float) $data['min_stock'], 3) : null,
            'active' => $data['active'] ?? true,
        ])->save();
        $ingredient = Ingredient::query()->withStock($this->outlet($request))->findOrFail($ingredient->id);
        Audit::record($before ? 'ingredient.updated' : 'ingredient.created', $ingredient, $before, InventoryService::present($ingredient));

        return response()->json(['data' => InventoryService::present($ingredient)], $before ? 200 : 201);
    }

    public function movements(Request $request, Ingredient $ingredient): JsonResponse
    {
        $this->guard();
        $outlet = $this->outlet($request);

        return response()->json(['data' => [
            'ingredient' => InventoryService::present(Ingredient::query()->withStock($outlet)->findOrFail($ingredient->id)),
            'movements' => $this->inventory->movements($ingredient, $outlet),
        ]]);
    }

    public function purchase(Request $request): JsonResponse
    {
        $this->guard();
        $data = $request->validate([
            'id' => ['required', 'uuid'],
            'supplier' => ['nullable', 'string', 'max:60'],
            'note' => ['nullable', 'string', 'max:120'],
            'paid_from_cash' => ['sometimes', 'boolean'],
            'outlet_id' => ['sometimes', 'uuid'],
            'lines' => ['required', 'array', 'min:1', 'max:50'],
            'lines.*.ingredient_id' => ['required', 'uuid'],
            'lines.*.qty' => self::QTY,
            'lines.*.total_cost' => ['required', 'integer', 'min:0', 'max:1000000000'],
        ]);

        $data['outlet_id'] = $this->outlet($request, $data['outlet_id'] ?? null);
        if (($data['paid_from_cash'] ?? false) && $data['outlet_id'] !== $request->attributes->get('device')->outlet_id) {
            throw ValidationException::withMessages(['paid_from_cash' => 'Bayar dari laci hanya untuk pembelian outlet tablet ini.']);
        }

        return response()->json(['data' => $this->inventory->purchase($data, $request->user(), $request->attributes->get('device'))], 201);
    }

    public function waste(Request $request): JsonResponse
    {
        $this->guard();
        $data = $request->validate([
            'id' => ['required', 'uuid'],
            'note' => ['required', 'string', 'max:120', 'regex:/\S/'],
            'outlet_id' => ['sometimes', 'uuid'],
            'lines' => ['required', 'array', 'min:1', 'max:50'],
            'lines.*.ingredient_id' => ['required', 'uuid'],
            'lines.*.qty' => self::QTY,
        ], ['note.required' => 'Tulis alasannya (mis. susu basi, gelas pecah).']);

        $data['outlet_id'] = $this->outlet($request, $data['outlet_id'] ?? null);

        return response()->json(['data' => $this->inventory->waste($data, $request->user(), $request->attributes->get('device'))], 201);
    }

    public function count(Request $request): JsonResponse
    {
        $this->guard();
        $data = $request->validate([
            'id' => ['required', 'uuid'],
            'note' => ['nullable', 'string', 'max:120'],
            'lines' => ['required', 'array', 'min:1', 'max:200'],
            'lines.*.ingredient_id' => ['required', 'uuid'],
            'lines.*.counted' => ['required', 'numeric', 'min:0', 'max:100000000'],
            'outlet_id' => ['sometimes', 'uuid'],
        ]);

        $data['outlet_id'] = $this->outlet($request, $data['outlet_id'] ?? null);

        return response()->json(['data' => $this->inventory->count($data, $request->user(), $request->attributes->get('device'))], 201);
    }

    /** Ganti resep satu produk (`product`) atau satu pilihan varian (`modifier`). */
    public function saveRecipe(Request $request, string $target, string $id): JsonResponse
    {
        $this->guard();
        $data = $request->validate([
            'items' => ['present', 'array', 'max:30'],
            'items.*.ingredient_id' => ['required', 'uuid'],
            'items.*.qty' => ['required', 'numeric', 'between:-100000,100000'],
        ]);
        $this->inventory->saveRecipe($target, $id, $data['items']);

        return response()->json(['data' => [
            'recipes' => $this->inventory->recipes(),
            'product_costs' => (object) $this->inventory->productCosts($this->outlet($request)),
        ]]);
    }

    /** Outlet yang dikelola: dari body / `?outlet=`, default outlet tablet ini. */
    private function outlet(Request $request, ?string $id = null): string
    {
        if ($id !== null) {
            abort_unless(Outlet::query()->whereKey($id)->exists(), 422, 'Outlet tidak ditemukan.');

            return $id;
        }

        return OutletFilter::resolve($request) ?? $request->attributes->get('device')->outlet_id;
    }

    private function guard(): void
    {
        abort_unless($this->inventory->enabled(), 403, 'Fitur stok & resep tidak aktif untuk kedai ini.');
    }
}
