<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Requests\SignupRequest;
use App\Http\Resources\SessionUserResource;
use App\Mail\SecurityAlertMail;
use App\Models\User;
use App\Support\Audit;
use App\Support\OwnerMailer;
use App\Support\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;
use Illuminate\Validation\ValidationException;

/**
 * Profil user yang sedang login (semua peran): nama & PIN sendiri. Owner juga email & password.
 * Ganti PIN / password / email selalu meminta PIN / password lama.
 */
class ProfileController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        $user = $request->user();
        $request->merge(['name' => preg_replace('/\s+/', ' ', trim((string) $request->input('name')))]);
        if (is_string($request->input('email'))) {
            $request->merge(['email' => strtolower(trim($request->input('email')))]);
        }
        $owner = $user->role === Role::Owner;
        $data = $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:40', 'regex:/^[\pL\pN .\'-]+$/u',
                Rule::unique('users', 'name')->where('tenant_id', $user->tenant_id)->ignore($user->id)],
            // Kasir tidak punya email (masuk dengan PIN): isian email diabaikan.
            ...($owner ? ['email' => ['required', 'email:rfc', 'max:255'], 'current_password' => ['nullable', 'string', 'max:255']] : []),
        ], [
            'name.unique' => 'Nama ini sudah dipakai pengguna lain di usaha ini.',
        ]);

        $before = ['name' => $user->name, 'email' => $user->email];
        $emailChanged = $owner && $data['email'] !== $user->email;
        if ($emailChanged) {
            // Ganti email = ganti akun masuk: wajib password, email belum dipakai usaha lain (lintas tenant).
            if (! Hash::check((string) ($data['current_password'] ?? ''), (string) $user->password)) {
                throw ValidationException::withMessages(['current_password' => 'Password salah.']);
            }
            $taken = app(TenantContext::class)->bypass(fn () => User::query()->where('email', $data['email'])->whereKeyNot($user->id)->exists());
            if ($taken) {
                throw ValidationException::withMessages(['email' => 'Email ini sudah terdaftar.']);
            }
            $user->email = $data['email'];
            $user->email_verified_at = null; // diverifikasi ulang lewat kode email
        }
        $user->name = $data['name'];
        $user->save();
        Audit::record('profile.updated', $user, $before, ['name' => $user->name, 'email' => $user->email], user: $user);

        return response()->json(['data' => new SessionUserResource($user)]);
    }

    public function updatePin(Request $request): JsonResponse
    {
        $user = $request->user();
        $data = $request->validate([
            'current_pin' => ['required', 'digits:6'],
            'pin' => ['required', 'digits:6', 'different:current_pin', function (string $attribute, mixed $value, Closure $fail) {
                if (SignupRequest::weakPin((string) $value)) {
                    $fail('PIN terlalu mudah ditebak. Hindari angka sama semua atau berurutan.');
                }
            }],
        ], ['pin.different' => 'PIN baru harus berbeda dari PIN lama.']);

        $this->checkPin($user, $data['current_pin']);
        $user->setPin($data['pin']);
        $user->save();
        // Sesi lain (tablet lain) ikut keluar; sesi ini tetap.
        $user->tokens()->whereKeyNot($user->currentAccessToken()->id)->delete();
        Audit::record('profile.pin_changed', $user, user: $user);

        return response()->json(['message' => 'PIN diganti.']);
    }

    public function updatePassword(Request $request): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->role === Role::Owner, 403, 'Hanya owner yang punya password.');
        $data = $request->validate([
            'current_password' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string', 'max:255', 'confirmed', 'different:current_password', Password::min(8)->letters()->numbers()],
        ], ['password.different' => 'Password baru harus berbeda dari password lama.']);

        if (! Hash::check($data['current_password'], (string) $user->password)) {
            throw ValidationException::withMessages(['current_password' => 'Password salah.']);
        }
        $user->password = $data['password'];
        $user->save();
        $user->tokens()->whereKeyNot($user->currentAccessToken()->id)->delete();
        Audit::record('profile.password_changed', $user, user: $user);
        $userId = $user->id;
        OwnerMailer::send($user->tenant_id, fn ($o, $t) => $o->id === $userId ? new SecurityAlertMail(
            ownerName: $o->name, businessName: $t->name, kind: SecurityAlertMail::PASSWORD_CHANGED, at: now(),
        ) : null);

        return response()->json(['message' => 'Password diganti.']);
    }

    /** PIN lama salah dihitung sebagai percobaan gagal (akun terkunci sementara setelah beberapa kali). */
    private function checkPin(User $user, string $pin): void
    {
        if ($user->isLocked()) {
            throw ValidationException::withMessages(['current_pin' => 'Terlalu banyak percobaan. Coba lagi nanti.']);
        }
        if (! Hash::check($pin, (string) $user->pin_hash)) {
            $user->registerFailedAttempt();
            Audit::record('auth.pin_failed', $user, user: $user);
            throw ValidationException::withMessages(['current_pin' => 'PIN lama salah.']);
        }
        $user->clearFailedAttempts();
    }
}
