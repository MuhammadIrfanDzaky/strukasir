<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\PinLoginRequest;
use App\Http\Resources\SessionUserResource;
use App\Models\PersonalAccessToken;
use App\Models\User;
use App\Support\Audit;
use App\Support\Tenancy\FeatureGate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AuthController extends Controller
{
    /** Token user berlaku satu hari kerja; setelah itu kasir login PIN lagi. */
    private const USER_TOKEN_HOURS = 16;

    /** Daftar staf untuk layar pilih-nama di tablet (token perangkat). */
    public function staff(): JsonResponse
    {
        $staff = User::query()
            ->where('active', true)
            ->whereNotNull('pin_hash')
            ->orderBy('role')
            ->orderBy('name')
            ->get(['id', 'name', 'role']);

        return response()->json([
            'data' => $staff->map(fn (User $u) => ['id' => $u->id, 'name' => $u->name, 'role' => $u->role->value]),
        ]);
    }

    public function pinLogin(PinLoginRequest $request): JsonResponse
    {
        $device = $request->attributes->get('device');
        // Ter-scope ke tenant perangkat: user_id milik kedai lain tidak akan ditemukan.
        $user = User::query()->whereKey((string) $request->input('user_id'))->where('active', true)->first();

        if ($user === null || $user->pin_hash === null) {
            return response()->json(['message' => 'PIN salah.'], 422);
        }

        if ($user->isLocked()) {
            return response()->json([
                'message' => 'Akun terkunci sementara karena terlalu banyak PIN salah.',
                'locked_until' => $user->locked_until->toIso8601String(),
            ], 423);
        }

        if (! Hash::check((string) $request->input('pin'), $user->pin_hash)) {
            $user->registerFailedAttempt();
            Audit::record('auth.pin_failed', $user, user: $user);

            return response()->json(['message' => 'PIN salah.'], 422);
        }

        $user->clearFailedAttempts();

        // Satu sesi aktif per user per tablet.
        PersonalAccessToken::query()
            ->where('tokenable_type', $user->getMorphClass())
            ->where('tokenable_id', $user->id)
            ->where('device_id', $device->id)
            ->delete();

        $token = $user->createToken('pin:'.$device->code, ['user'], now()->addHours(self::USER_TOKEN_HOURS));
        $token->accessToken->forceFill(['device_id' => $device->id])->save();

        Audit::record('auth.login', $user, user: $user);

        return response()->json([
            'token' => $token->plainTextToken,
            'expires_at' => $token->accessToken->expires_at->toIso8601String(),
            'user' => new SessionUserResource($user),
        ]);
    }

    public function me(Request $request, FeatureGate $features): JsonResponse
    {
        $tenant = $request->attributes->get('tenant');
        $device = $request->attributes->get('device');

        return response()->json([
            'user' => new SessionUserResource($request->user()),
            'tenant' => ['id' => $tenant->id, 'name' => $tenant->name, 'timezone' => $tenant->timezone],
            'device' => ['id' => $device->id, 'code' => $device->code, 'name' => $device->name],
            'features' => $features->forTenant($tenant->id),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();
        Audit::record('auth.logout', $request->user());

        return response()->json(['message' => 'Berhasil keluar.']);
    }
}
