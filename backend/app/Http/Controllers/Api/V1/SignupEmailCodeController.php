<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\SignupCodes;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Langkah sebelum daftar: kirim kode verifikasi ke email calon owner. Usaha baru dibuat
 * hanya bila kode ini benar (POST /signup dengan `email_code`), jadi email pasti milik pendaftar.
 */
class SignupEmailCodeController extends Controller
{
    public function __invoke(Request $request, SignupCodes $codes): JsonResponse
    {
        $request->merge(['email' => is_string($request->input('email')) ? strtolower(trim($request->input('email'))) : null]);
        $data = $request->validate([
            'email' => ['required', 'email:rfc', 'max:255', 'unique:users,email'],
            'owner_name' => ['nullable', 'string', 'max:60'],
        ], [
            'email.unique' => 'Email ini sudah terdaftar. Pilih "Masuk" untuk mendaftarkan tablet ke usaha yang sudah ada.',
        ]);

        return match ($codes->send($data['email'], $data['owner_name'] ?? '')) {
            SignupCodes::SENT => response()->json(['message' => "Kode dikirim ke {$data['email']}. Periksa juga folder spam."]),
            SignupCodes::WAIT => response()->json(['message' => 'Kode baru saja dikirim. Tunggu 1 menit sebelum minta lagi.'], 429),
            default => response()->json(['message' => 'Email gagal dikirim. Periksa alamat email atau coba lagi nanti.'], 503),
        };
    }
}
