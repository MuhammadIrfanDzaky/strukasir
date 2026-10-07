<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\EmailCodes;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/** Owner yang sedang login memverifikasi emailnya (supaya reset password pasti sampai ke orang yang benar). */
class EmailVerificationController extends Controller
{
    public function send(Request $request, EmailCodes $codes): JsonResponse
    {
        $user = $request->user();
        abort_if($user->email === null, 404);
        if ($user->email_verified_at !== null) {
            return response()->json(['message' => 'Email sudah terverifikasi.']);
        }

        if (! $codes->canSend($user, EmailCodes::VERIFY_EMAIL)) {
            return response()->json(['message' => 'Kode baru saja dikirim. Tunggu 1 menit sebelum minta lagi.'], 429);
        }
        if (! $codes->send($user, EmailCodes::VERIFY_EMAIL)) {
            return response()->json(['message' => 'Email gagal dikirim. Coba lagi nanti.'], 503);
        }

        return response()->json(['message' => "Kode dikirim ke {$user->email}. Periksa juga folder spam."]);
    }

    public function verify(Request $request, EmailCodes $codes): JsonResponse
    {
        $data = $request->validate(['code' => ['required', 'string', 'max:10']]);
        $user = $request->user();
        abort_if($user->email === null, 404);

        return DB::transaction(function () use ($user, $data, $codes) {
            if (! $codes->consume($user, EmailCodes::VERIFY_EMAIL, trim($data['code']))) {
                return response()->json([
                    'message' => 'Kode salah atau sudah kedaluwarsa.',
                    'errors' => ['code' => ['Kode salah atau sudah kedaluwarsa.']],
                ], 422);
            }

            $user->email_verified_at = now();
            $user->save();
            Audit::record('auth.email_verified', $user);

            return response()->json(['message' => 'Email terverifikasi.', 'email_verified' => true]);
        });
    }
}
