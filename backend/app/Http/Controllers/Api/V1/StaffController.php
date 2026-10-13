<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Requests\SignupRequest;
use App\Models\Tenant;
use App\Models\User;
use App\Services\SubscriptionService;
use App\Support\Audit;
use App\Support\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Pengaturan → Pegawai (owner, izin users.manage): tambah kasir, ganti nama, reset PIN, nonaktifkan.
 * Akun owner tampil tetapi tidak diubah di sini. Pegawai tidak dihapus (riwayat order merujuknya).
 */
class StaffController extends Controller
{
    public function index(): JsonResponse
    {
        $users = User::query()->orderByRaw("role = 'owner' desc")->orderByDesc('active')->orderBy('name')->get();

        return response()->json(['data' => $users->map(fn (User $u) => self::present($u))->values()]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([...$this->nameRule($request), 'pin' => self::pinRule()]);

        $user = DB::transaction(function () use ($data) {
            Tenant::query()->whereKey(app(TenantContext::class)->id())->lockForUpdate()->first();
            app(SubscriptionService::class)->assertLimit('staff', User::query()->where('active', true)->count());
            $user = new User(['name' => $data['name']]);
            $user->role = Role::Cashier;
            $user->setPin($data['pin']);
            $user->save();

            return $user;
        });
        Audit::record('staff.created', $user, after: ['name' => $user->name, 'role' => $user->role->value]);

        return response()->json(['data' => self::present($user->refresh())], 201);
    }

    public function update(Request $request, User $staff): JsonResponse
    {
        $this->guardCashier($staff);
        $data = $request->validate([...$this->nameRule($request, $staff), 'active' => ['sometimes', 'boolean']]);

        $before = self::present($staff);
        $staff->name = $data['name'];
        if (array_key_exists('active', $data)) {
            if ($data['active'] && ! $staff->active) {
                app(SubscriptionService::class)->assertLimit('staff', User::query()->where('active', true)->count());
            }
            $staff->active = $data['active'];
        }
        $staff->save();
        if (! $staff->active) {
            $staff->tokens()->delete(); // dinonaktifkan → keluar dari semua tablet
        }
        Audit::record('staff.updated', $staff, $before, self::present($staff));

        return response()->json(['data' => self::present($staff)]);
    }

    /** PIN baru (kasir lupa PIN / PIN bocor): buka kunci & keluarkan dari semua tablet. */
    public function resetPin(Request $request, User $staff): JsonResponse
    {
        $this->guardCashier($staff);
        $data = $request->validate(['pin' => self::pinRule()]);

        $staff->setPin($data['pin']);
        $staff->failed_attempts = 0;
        $staff->locked_until = null;
        $staff->save();
        $staff->tokens()->delete();
        Audit::record('staff.pin_reset', $staff, after: ['name' => $staff->name]);

        return response()->json(['data' => self::present($staff)]);
    }

    /** @return array<string, mixed> */
    public static function present(User $u): array
    {
        return [
            'id' => $u->id,
            'name' => $u->name,
            'role' => $u->role->value,
            'active' => $u->active,
            'locked' => $u->isLocked(),
            'has_pin' => $u->pin_hash !== null,
            'created_at' => $u->created_at?->toIso8601String(),
        ];
    }

    private function guardCashier(User $staff): void
    {
        abort_unless($staff->role === Role::Cashier, 403, 'Akun owner tidak diubah dari sini.');
    }

    /** @return array<string, list<mixed>> */
    private function nameRule(Request $request, ?User $ignore = null): array
    {
        $request->merge(['name' => preg_replace('/\s+/', ' ', trim((string) $request->input('name')))]);

        return ['name' => ['required', 'string', 'min:2', 'max:40', 'regex:/^[\pL\pN .\'-]+$/u',
            Rule::unique('users', 'name')->where('tenant_id', $request->user()->tenant_id)->ignore($ignore?->id)]];
    }

    /** PIN 6 digit, tidak boleh mudah ditebak (aturan sama dengan pendaftaran owner). */
    private static function pinRule(): array
    {
        return ['required', 'digits:6', function (string $attribute, mixed $value, Closure $fail) {
            if (SignupRequest::weakPin((string) $value)) {
                $fail('PIN terlalu mudah ditebak. Hindari angka sama semua atau berurutan.');
            }
        }];
    }
}
