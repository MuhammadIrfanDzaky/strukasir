<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\ModifierGroupRequest;
use App\Models\Modifier;
use App\Models\ModifierGroup;
use App\Models\Product;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * Grup modifier disimpan bersama pilihannya dalam satu request. Pilihan yang tidak dikirim
 * dinonaktifkan (bukan dihapus), agar riwayat dan audit tetap bisa ditelusuri.
 */
class ModifierGroupController extends Controller
{
    public function store(ModifierGroupRequest $request): JsonResponse
    {
        $group = DB::transaction(function () use ($request) {
            $group = ModifierGroup::create($this->attributes($request));
            $this->saveModifiers($group, $request->validated('modifiers'));
            $this->applyToExisting($group, $request);

            return $group;
        });

        Audit::record('modifier_group.created', $group, after: $this->snapshot($group));

        return response()->json(['id' => $group->id], 201);
    }

    public function update(ModifierGroupRequest $request, ModifierGroup $modifierGroup): JsonResponse
    {
        $before = $this->snapshot($modifierGroup);

        DB::transaction(function () use ($request, $modifierGroup) {
            $modifierGroup->update($this->attributes($request));
            $this->saveModifiers($modifierGroup, $request->validated('modifiers'));
            $this->applyToExisting($modifierGroup, $request);
            $modifierGroup->touch();
        });

        $after = $this->snapshot($modifierGroup->refresh());
        if ($before !== $after) {
            Audit::record('modifier_group.updated', $modifierGroup, $before, $after);
        }

        return response()->json(['id' => $modifierGroup->id]);
    }

    public function destroy(ModifierGroup $modifierGroup): JsonResponse
    {
        Audit::record('modifier_group.deleted', $modifierGroup, before: $this->snapshot($modifierGroup));
        $modifierGroup->delete(); // modifier & relasi produk ikut terhapus (cascade); snapshot order tetap utuh

        return response()->json(null, 204);
    }

    /** @return array<string, mixed> */
    private function attributes(ModifierGroupRequest $request): array
    {
        $data = $request->safe()->except(['modifiers', 'apply_to_existing']);
        if (array_key_exists('category_ids', $data)) {
            $data['category_ids'] = empty($data['category_ids']) ? null : array_values($data['category_ids']);
        }

        return $data;
    }

    /** Pasang grup ke produk yang sudah ada di kategorinya (yang belum memakai grup ini), di urutan terakhir. */
    private function applyToExisting(ModifierGroup $group, ModifierGroupRequest $request): void
    {
        if (! $request->boolean('apply_to_existing') || empty($group->category_ids)) {
            return;
        }
        $products = Product::query()->whereIn('category_id', $group->category_ids)
            ->whereDoesntHave('modifierGroups', fn ($q) => $q->whereKey($group->id))->get();
        foreach ($products as $product) {
            $sort = (int) DB::table('product_modifier_groups')->where('product_id', $product->id)->max('sort') + 1;
            $product->modifierGroups()->attach($group->id, ['tenant_id' => $product->tenant_id, 'sort' => $sort]);
        }
        Product::query()->whereKey($products->modelKeys())->update(['updated_at' => now()]); // versi menu berubah
    }

    /** @param  list<array{id?: string|null, name: string, price_delta: int, active?: bool}>  $items */
    private function saveModifiers(ModifierGroup $group, array $items): void
    {
        $kept = [];

        foreach (array_values($items) as $sort => $item) {
            $modifier = isset($item['id'])
                ? $group->modifiers()->findOrFail($item['id'])
                : new Modifier(['modifier_group_id' => $group->id]);

            $modifier->fill([
                'name' => $item['name'],
                'price_delta' => $item['price_delta'],
                'active' => $item['active'] ?? true,
                'sort' => $sort,
            ])->save();

            $kept[] = $modifier->id;
        }

        $group->modifiers()->whereNotIn('id', $kept)->update(['active' => false]);
    }

    /** @return array<string, mixed> */
    private function snapshot(ModifierGroup $group): array
    {
        return [
            'name' => $group->name,
            'min_select' => $group->min_select,
            'max_select' => $group->max_select,
            'allow_quantity' => $group->allow_quantity,
            'max_quantity' => $group->max_quantity,
            'category_ids' => $group->category_ids,
            'modifiers' => $group->modifiers()->get(['name', 'price_delta', 'active'])->toArray(),
        ];
    }
}
