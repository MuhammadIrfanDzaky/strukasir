<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;

/** Publik: dicek tablet saat dibuka untuk memaksa update bila versinya terlalu lama. */
class AppVersionController extends Controller
{
    public function __invoke(): JsonResponse
    {
        return response()->json([
            'latest_version' => config('pos.app.latest_version'),
            'min_version' => config('pos.app.min_version'),
            'download_url' => config('pos.app.download_url'),
        ]);
    }
}
