<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\Modifier;
use App\Models\ModifierGroup;
use App\Models\Product;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * Snapshot menu lengkap untuk di-cache tablet. `version` berubah setiap ada perubahan menu,
 * sehingga tablet cukup membandingkan versi sebelum mengunduh ulang.
 */
class MenuController extends Controller
{
    public function show(): JsonResponse
    {
        $groups = ModifierGroup::query()->with('modifiers')->orderBy('sort')->orderBy('name')->get();
        $products = Product::query()->orderBy('sort')->orderBy('name')->get();
        $productGroups = DB::table('product_modifier_groups')->orderBy('sort')->get()->groupBy('product_id');

        return response()->json([
            'version' => $this->version(),
            'categories' => Category::query()->orderBy('sort')->orderBy('name')->get()
                ->map(fn (Category $c) => [
                    'id' => $c->id, 'name' => $c->name, 'sort' => $c->sort, 'active' => $c->active,
                ]),
            'products' => $products->map(fn (Product $p) => [
                'id' => $p->id,
                'category_id' => $p->category_id,
                'name' => $p->name,
                'price' => $p->price,
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
        $stamps = collect(['categories', 'products', 'modifier_groups', 'modifiers'])
            ->map(fn (string $table) => DB::table($table)->selectRaw('count(*) as n, max(updated_at) as t')->first())
            ->map(fn ($row) => $row->n.'@'.$row->t)
            ->implode('|');

        return substr(sha1($stamps), 0, 16);
    }
}
