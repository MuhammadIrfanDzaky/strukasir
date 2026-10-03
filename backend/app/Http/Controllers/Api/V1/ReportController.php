<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\ReportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ReportController extends Controller
{
    /** Ringkasan penjualan per rentang hari bisnis (maks 366 hari). */
    public function summary(Request $request, ReportService $reports): JsonResponse
    {
        $data = $request->validate([
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d', 'after_or_equal:from'],
        ]);
        abort_if(now()->parse($data['from'])->diffInDays($data['to']) > 366, 422, 'Rentang maksimal 1 tahun.');

        return response()->json(['data' => $reports->summary($data['from'], $data['to'])]);
    }
}
