<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Kode email sekali pakai (hash). Dikelola hanya lewat App\Services\EmailCodes. */
class EmailCode extends Model
{
    use HasUuids;

    public const UPDATED_AT = null;

    protected $fillable = [];

    protected $hidden = ['code_hash'];

    protected function casts(): array
    {
        return [
            'attempts' => 'integer',
            'expires_at' => 'datetime',
            'used_at' => 'datetime',
        ];
    }
}
