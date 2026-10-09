<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\CustomerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POST /customers/import {csv, dry_run}: sama seperti import produk (pratinjau dulu,
 * semua-atau-tidak-sama-sekali). Kolom: Nama (wajib), No HP, Tanggal lahir, Catatan.
 */
class CustomerImportController extends Controller
{
    private const MAX_CSV = 524_288;

    public function __invoke(Request $request, CustomerService $customers): JsonResponse
    {
        $data = $request->validate([
            'csv' => ['required', 'string', 'max:'.self::MAX_CSV],
            'dry_run' => ['sometimes', 'boolean'],
        ]);

        $result = $customers->import($data['csv'], (bool) ($data['dry_run'] ?? false));

        return response()->json(['data' => $result], $result['errors'] === [] ? 200 : 422);
    }
}
