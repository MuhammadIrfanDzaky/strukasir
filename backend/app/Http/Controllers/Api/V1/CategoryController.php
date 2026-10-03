<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\CategoryRequest;
use App\Models\Category;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;

class CategoryController extends Controller
{
    public function store(CategoryRequest $request): JsonResponse
    {
        $category = Category::create($request->validated());
        Audit::record('category.created', $category, after: $category->only(['name', 'active']));

        return response()->json(['id' => $category->id], 201);
    }

    public function update(CategoryRequest $request, Category $category): JsonResponse
    {
        $before = $category->only(['name', 'sort', 'active']);
        $category->update($request->validated());

        if ($category->wasChanged()) {
            Audit::record('category.updated', $category, $before, $category->only(['name', 'sort', 'active']));
        }

        return response()->json(['id' => $category->id]);
    }

    /** Kategori yang masih berisi produk tidak bisa dihapus; nonaktifkan saja. */
    public function destroy(Category $category): JsonResponse
    {
        if ($category->products()->exists()) {
            return response()->json([
                'message' => 'Kategori masih berisi produk. Pindahkan produknya atau nonaktifkan kategori.',
            ], 409);
        }

        Audit::record('category.deleted', $category, before: $category->only(['name']));
        $category->delete();

        return response()->json(null, 204);
    }
}
