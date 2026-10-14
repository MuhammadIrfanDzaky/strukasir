<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Mail\SecurityAlertMail;
use App\Models\User;
use App\Services\EmailCodes;
use App\Support\Audit;
use App\Support\OwnerMailer;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rules\Password;

/**
 * Lupa password owner (publik): minta kode ke email → kirim kode + password baru.
 * Respons "minta kode" selalu sama agar tidak bisa dipakai menebak email terdaftar (SEC-17).
 * 2FA tidak dilewati: mendaftarkan tablet tetap butuh kode authenticator bila aktif.
 */
class PasswordResetController extends Controller
{
    public function forgot(Request $request, EmailCodes $codes, TenantContext $context): JsonResponse
    {
        $data = $request->validate(['email' => ['required', 'email', 'max:255']]);

        $owner = $this->owner($data['email']);
        if ($owner !== null) {
            $context->run($owner->tenant_id, function () use ($owner, $codes) {
                if ($codes->send($owner, EmailCodes::RESET_PASSWORD)) {
                    Audit::record('auth.password_reset_requested', $owner, user: $owner);
                }
            });
        }

        return response()->json([
            'message' => 'Bila email terdaftar sebagai owner, kode reset sudah dikirim. Periksa juga folder spam.',
        ]);
    }

    public function reset(Request $request, EmailCodes $codes, TenantContext $context): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email', 'max:255'],
            'code' => ['required', 'string', 'max:10'],
            'password' => ['required', 'string', 'max:255', Password::min(8)->letters()->numbers()],
        ]);

        $invalid = response()->json([
            'message' => 'Kode salah atau sudah kedaluwarsa.',
            'errors' => ['code' => ['Kode salah atau sudah kedaluwarsa. Minta kode baru bila perlu.']],
        ], 422);

        $owner = $this->owner($data['email']);
        if ($owner === null) {
            return $invalid;
        }

        return $context->run($owner->tenant_id, fn () => DB::transaction(function () use ($owner, $data, $codes, $invalid) {
            if (! $codes->consume($owner, EmailCodes::RESET_PASSWORD, trim($data['code']))) {
                Audit::record('auth.password_reset_failed', $owner, user: $owner);

                return $invalid;
            }

            $owner->password = $data['password'];
            // Kode dari kotak masuk = bukti email milik owner.
            $owner->email_verified_at ??= now();
            $owner->failed_attempts = 0;
            $owner->locked_until = null;
            $owner->save();
            Audit::record('auth.password_reset', $owner, user: $owner);
            $ownerId = $owner->id;
            OwnerMailer::send($owner->tenant_id, fn ($o, $t) => $o->id === $ownerId ? new SecurityAlertMail(
                ownerName: $o->name, businessName: $t->name, kind: SecurityAlertMail::PASSWORD_CHANGED, at: now(),
            ) : null);

            return response()->json(['message' => 'Password diganti. Silakan masuk dengan password baru.']);
        }));
    }

    private function owner(string $email): ?User
    {
        return User::query()
            ->where('email', strtolower(trim($email)))
            ->where('role', Role::Owner)->where('active', true)
            ->first();
    }
}
