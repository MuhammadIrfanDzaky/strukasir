<?php

use App\Http\Middleware\ResolveTenant;
use App\Http\Middleware\SecurityHeaders;
use App\Support\Tenancy\MissingTenantContext;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Routing\Middleware\SubstituteBindings;
use Sentry\Laravel\Integration;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias(['tenant' => ResolveTenant::class, 'plan.active' => \App\Http\Middleware\EnsurePlanActive::class]);
        // Tenant harus diketahui SEBELUM route model binding, supaya {product} milik kedai lain = 404.
        $middleware->prependToPriorityList(SubstituteBindings::class, ResolveTenant::class);
        // Global (paling luar) agar respons error seperti 401/429 juga membawa header keamanan.
        $middleware->prepend(SecurityHeaders::class);
        $middleware->throttleApi('api');
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // API selalu menjawab JSON, termasuk 401/404/422/429.
        $exceptions->shouldRenderJsonWhen(fn (Request $request) => $request->is('api/*') || $request->expectsJson());

        // Bug isolasi tenant: catat lengkap di log, tapi jawab generik ke klien (SEC-25).
        $exceptions->render(function (MissingTenantContext $e, Request $request) {
            report($e);

            return response()->json(['message' => 'Terjadi kesalahan server.'], 500);
        });
        $exceptions->dontReportDuplicates();

        // Kirim error ke Sentry bila SENTRY_LARAVEL_DSN diisi; tanpa DSN tidak melakukan apa-apa.
        Integration::handles($exceptions);
    })->create();
