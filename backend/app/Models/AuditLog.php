<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Append-only (dijaga trigger database). Tulis lewat App\Support\Audit. */
class AuditLog extends Model
{
    use BelongsToTenant, HasUuids;

    public const UPDATED_AT = null;

    protected $fillable = ['user_id', 'device_id', 'action', 'entity_type', 'entity_id', 'before', 'after', 'ip'];

    protected function casts(): array
    {
        return [
            'before' => 'array',
            'after' => 'array',
        ];
    }
}
