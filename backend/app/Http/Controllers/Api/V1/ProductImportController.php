<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\ProductImportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POST /products/import {csv, dry_run}. `dry_run=true` hanya memeriksa & menghitung (pratinjau);
 * tanpa dry_run data disimpan, kecuali ada baris yang salah (semua-atau-tidak-sama-sekali).
 */
class ProductImportController extends Controller
{
    /** CSV dikirim sebagai teks: 512 KB cukup untuk ±1.000 produk. */
    private const MAX_CSV = 524_288;

    public function __invoke(Request $request, ProductImportService $import): JsonResponse
    {
        $data = $request->validate([
            'csv' => ['required', 'string', 'max:'.self::MAX_CSV],
            'dry_run' => ['sometimes', 'boolean'],
        ]);

        $result = $import->import($data['csv'], (bool) ($data['dry_run'] ?? false));

        return response()->json(['data' => $result], $result['errors'] === [] ? 200 : 422);
    }
}
