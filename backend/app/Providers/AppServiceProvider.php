<?php

namespace App\Providers;

use App\Enums\Permission;
use App\Models\PersonalAccessToken;
use App\Models\User;
use App\Support\Tenancy\FeatureGate;
use App\Support\Tenancy\TenantContext;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;
use Laravel\Sanctum\Sanctum;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->scoped(TenantContext::class);
        $this->app->scoped(FeatureGate::class);
    }

    public function boot(): void
    {
        Model::shouldBeStrict(! $this->app->isProduction());

        Sanctum::usePersonalAccessTokenModel(PersonalAccessToken::class);

        // Izin = role user ∩ fitur yang aktif untuk kedainya (dua dimensi, dicek di server).
        foreach (Permission::cases() as $permission) {
            Gate::define($permission->value, function (User $user) use ($permission) {
                if (! $user->active || ! $user->role->allows($permission)) {
                    return false;
                }

                $feature = $permission->requiredFeature();

                return $feature === null || app(FeatureGate::class)->enabled($feature, $user->tenant_id);
            });
        }

        RateLimiter::for('api', fn (Request $request) => Limit::perMinute(120)
            ->by($request->user()?->currentAccessToken()?->id ?: $request->ip()));

        // Login PIN/password: ketat per IP. Lockout per akun ada di User::registerFailedAttempt().
        RateLimiter::for('auth', fn (Request $request) => Limit::perMinute(10)->by('auth:'.$request->ip()));

        // Pendaftaran usaha: cegah pembuatan kedai massal dari satu IP (salah isi form tetap leluasa).
        RateLimiter::for('signup', fn (Request $request) => [
            Limit::perMinute(10)->by('signup-min:'.$request->ip()),
            Limit::perHour(5)->by('signup:'.$request->ip())->after(fn ($response) => $response->getStatusCode() === 201),
        ]);
    }
}
