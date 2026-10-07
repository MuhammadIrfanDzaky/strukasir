<?php

namespace App\Http\Resources;

use App\Enums\Permission;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Gate;

/** Profil user yang login + izin efektifnya (role ∩ fitur kedai). */
class SessionUserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'role' => $this->role->value,
            // Hanya owner yang punya email (login password); kasir cukup PIN.
            'email' => $this->email,
            'email_verified' => $this->email === null || $this->email_verified_at !== null,
            'permissions' => collect(Permission::cases())
                ->filter(fn (Permission $p) => Gate::forUser($this->resource)->allows($p->value))
                ->map(fn (Permission $p) => $p->value)
                ->values(),
        ];
    }
}
