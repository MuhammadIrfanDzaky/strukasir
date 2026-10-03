<?php

namespace App\Support;

use App\Enums\Permission;
use App\Models\User;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Persetujuan atasan di tablet kasir: owner memasukkan PIN-nya untuk mengizinkan aksi yang
 * tidak boleh dilakukan kasir sendiri (diskon di atas batas, void). Lockout & audit sama dengan login PIN.
 */
class Approval
{
    /**
     * @param  array{user_id?: string, pin?: string}|null  $approval
     *
     * @throws ValidationException
     */
    public static function verify(?array $approval, Permission $permission, string $field = 'approval'): User
    {
        if (empty($approval['user_id']) || empty($approval['pin'])) {
            throw ValidationException::withMessages([$field => 'Butuh persetujuan owner (PIN).']);
        }

        // Ter-scope ke tenant aktif: approver dari kedai lain tidak akan ditemukan.
        $approver = User::query()->whereKey($approval['user_id'])->where('active', true)->first();

        if ($approver === null || ! Gate::forUser($approver)->allows($permission->value)) {
            throw ValidationException::withMessages([$field => 'Penyetuju tidak berwenang.']);
        }

        if ($approver->isLocked()) {
            throw ValidationException::withMessages([$field => 'Akun penyetuju terkunci sementara.']);
        }

        if (! Hash::check((string) $approval['pin'], (string) $approver->pin_hash)) {
            $approver->registerFailedAttempt();
            Audit::record('approval.pin_failed', $approver, after: ['permission' => $permission->value]);

            throw ValidationException::withMessages([$field => 'PIN penyetuju salah.']);
        }

        $approver->clearFailedAttempts();

        return $approver;
    }
}
