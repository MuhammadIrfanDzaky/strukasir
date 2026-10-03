<?php

namespace App\Support\Tenancy;

use RuntimeException;

/**
 * Query ke data milik tenant tanpa konteks tenant. Sengaja gagal keras (fail closed)
 * daripada diam-diam mengembalikan data semua tenant.
 */
class MissingTenantContext extends RuntimeException
{
    public static function for(string $model): self
    {
        return new self("No tenant context while accessing {$model}.");
    }
}
