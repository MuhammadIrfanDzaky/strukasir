<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\BusinessGroup;
use App\Enums\BusinessSector;
use App\Enums\SalesMode;
use App\Http\Controllers\Controller;
use App\Support\Regions;
use Illuminate\Http\JsonResponse;

/**
 * Pilihan untuk form "Daftar usaha baru" (publik, data statis): jenis usaha berkelompok,
 * cara berjualan, dan provinsi + kota/kabupaten. Satu sumber untuk app & validasi server.
 */
class SignupOptionsController extends Controller
{
    public function __invoke(): JsonResponse
    {
        $sectors = collect(BusinessGroup::cases())->map(fn (BusinessGroup $group) => [
            'group' => $group->value,
            'label' => $group->label(),
            'items' => collect(BusinessSector::cases())
                ->filter(fn (BusinessSector $s) => $s->group() === $group)
                ->map(fn (BusinessSector $s) => ['code' => $s->value, 'label' => $s->label(), 'asks_sales_mode' => $s->asksSalesMode()])
                ->values(),
        ]);

        return response()->json([
            'sectors' => $sectors,
            'sales_modes' => collect(SalesMode::cases())->map(fn (SalesMode $m) => ['code' => $m->value, 'label' => $m->label()]),
            'regions' => Regions::all(),
        ])->header('Cache-Control', 'public, max-age=86400');
    }
}
