<?php

namespace App\Support\Tenancy;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

class TenantScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        $context = app(TenantContext::class);

        if ($context->bypassing()) {
            return;
        }

        if ($context->has()) {
            $builder->where($model->qualifyColumn('tenant_id'), $context->id());

            return;
        }

        // Model identitas (User, Device) dibaca saat resolusi token, sebelum tenant diketahui.
        if (! $model->requiresTenantContext()) {
            return;
        }

        throw MissingTenantContext::for($model::class);
    }
}
