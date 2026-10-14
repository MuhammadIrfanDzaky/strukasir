<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\Payments\SubscriptionCheckout;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Notifikasi pembayaran Midtrans (publik, tanpa token). Diatur di dashboard Midtrans →
 * Settings → Payment → Notification URL: https://<domain>/api/v1/payments/midtrans/notification
 */
class MidtransNotificationController extends Controller
{
    public function __invoke(Request $request, SubscriptionCheckout $checkout): JsonResponse
    {
        if (! $checkout->handleNotification($request->json()->all())) {
            return response()->json(['message' => 'Tanda tangan tidak valid.'], 403);
        }

        return response()->json(['message' => 'OK']);
    }
}
