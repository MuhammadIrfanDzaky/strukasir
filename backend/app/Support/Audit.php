<?php

namespace App\Support;

use App\Models\AuditLog;
use App\Models\Device;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;

/**
 * Pencatat audit trail: siapa (user/perangkat), apa, sebelum, sesudah, kapan, dari IP mana.
 * Jangan pernah memasukkan password, PIN, atau token ke before/after.
 */
class Audit
{
    /**
     * @param  array<string, mixed>|null  $before
     * @param  array<string, mixed>|null  $after
     */
    public static function record(
        string $action,
        ?Model $entity = null,
        ?array $before = null,
        ?array $after = null,
        ?User $user = null,
        ?Device $device = null,
    ): AuditLog {
        $request = request();
        $actor = $request->user();

        return AuditLog::create([
            'user_id' => $user?->id ?? ($actor instanceof User ? $actor->id : null),
            'device_id' => $device?->id ?? $request->attributes->get('device')?->id
                ?? ($actor instanceof Device ? $actor->id : null),
            'action' => $action,
            'entity_type' => $entity ? class_basename($entity) : null,
            'entity_id' => $entity?->getKey(),
            'before' => $before,
            'after' => $after,
            'ip' => $request->ip(),
        ]);
    }
}
