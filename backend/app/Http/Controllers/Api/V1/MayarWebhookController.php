<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\Payments\SubscriptionCheckout;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Webhook Mayar (publik). Mayar tidak menandatangani webhook, jadi URL memuat token rahasia
 * (`MAYAR_WEBHOOK_TOKEN`) dan isi webhook tidak dipercaya: status selalu dicek ulang ke API Mayar.
 * Daftarkan di Mayar → Integration → Webhook: https://<domain>/api/v1/payments/mayar/webhook?token=<token>
 */
class MayarWebhookController extends Controller
{
    public function __invoke(Request $request, SubscriptionCheckout $checkout): JsonResponse
    {
        $token = (string) config('services.mayar.webhook_token');
        if ($token === '' || ! hash_equals($token, (string) $request->query('token'))) {
            return response()->json(['message' => 'Token tidak valid.'], 403);
        }
        if ($checkout->enabled()) {
            $checkout->handleWebhook($request->json()->all());
        }

        return response()->json(['message' => 'OK']);
    }
}
