<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\ProductRequest;
use App\Models\Product;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * Produk tidak dihapus (riwayat order merujuknya); gunakan `active=false`.
 * Setiap perubahan nama/harga/status tercatat di audit log dengan nilai sebelum & sesudah.
 */
class ProductController extends Controller
{
    private const AUDITED = ['category_id', 'code', 'name', 'price', 'cost', 'active', 'sold_out', 'favorite'];

    public function store(ProductRequest $request): JsonResponse
    {
        $product = DB::transaction(function () use ($request) {
            $product = Product::create($request->safe()->except('modifier_group_ids'));
            $this->syncGroups($product, $request->validated('modifier_group_ids', []));

            return $product;
        });

        Audit::record('product.created', $product, after: $product->only(self::AUDITED));

        return response()->json(['id' => $product->id], 201);
    }

    public function update(ProductRequest $request, Product $product): JsonResponse
    {
        $before = $product->only(self::AUDITED);

        DB::transaction(function () use ($request, $product) {
            $product->update($request->safe()->except('modifier_group_ids'));

            if ($request->has('modifier_group_ids')) {
                $this->syncGroups($product, $request->validated('modifier_group_ids'));
                $product->touch(); // ubah versi menu walau hanya relasi yang berubah
            }
        });

        $after = $product->only(self::AUDITED);
        if ($before !== $after) {
            Audit::record('product.updated', $product, $before, $after);
        }

        return response()->json(['id' => $product->id]);
    }

    /** @param  list<string>  $groupIds  urutan = urutan tampil di tablet */
    private function syncGroups(Product $product, array $groupIds): void
    {
        $product->modifierGroups()->sync(collect($groupIds)->values()->mapWithKeys(
            fn (string $id, int $i) => [$id => ['tenant_id' => $product->tenant_id, 'sort' => $i]],
        )->all());
    }
}
