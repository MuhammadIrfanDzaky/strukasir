<?php

use App\Enums\Permission;
use App\Http\Controllers\Api\V1\AppVersionController;
use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\DeviceRegistrationController;
use App\Http\Controllers\Api\V1\DeviceUnregisterController;
use App\Http\Controllers\Api\V1\EmailVerificationController;
use App\Http\Controllers\Api\V1\FeatureSettingsController;
use App\Http\Controllers\Api\V1\MenuController;
use App\Http\Controllers\Api\V1\ModifierGroupController;
use App\Http\Controllers\Api\V1\OrderController;
use App\Http\Controllers\Api\V1\PasswordResetController;
use App\Http\Controllers\Api\V1\ProductController;
use App\Http\Controllers\Api\V1\ProductImportController;
use App\Http\Controllers\Api\V1\ReceiptSettingsController;
use App\Http\Controllers\Api\V1\ReportController;
use App\Http\Controllers\Api\V1\ShiftController;
use App\Http\Controllers\Api\V1\SignupController;
use App\Http\Controllers\Api\V1\SignupOptionsController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::get('app/version', AppVersionController::class);

    // Publik: owner mendaftarkan tablet dengan email + password.
    Route::post('devices/register', DeviceRegistrationController::class)->middleware('throttle:auth');
    // Publik: pendaftaran usaha baru (tablet ini otomatis jadi tablet pertama).
    Route::post('signup', SignupController::class)->middleware('throttle:signup');
    Route::get('signup/options', SignupOptionsController::class); // jenis usaha & wilayah untuk form daftar
    // Publik: lupa password owner (kode 6 digit ke email).
    Route::post('auth/password/forgot', [PasswordResetController::class, 'forgot'])->middleware('throttle:auth');
    Route::post('auth/password/reset', [PasswordResetController::class, 'reset'])->middleware('throttle:auth');

    // Token perangkat: pilih nama staf lalu login PIN.
    Route::middleware(['auth:sanctum', 'tenant:device'])->group(function () {
        Route::get('auth/staff', [AuthController::class, 'staff']);
        Route::post('auth/pin', [AuthController::class, 'pinLogin'])->middleware('throttle:auth');
    });

    // Token user (hasil login PIN): semua operasi POS.
    Route::middleware(['auth:sanctum', 'tenant:user'])->group(function () {
        Route::get('auth/me', [AuthController::class, 'me']);
        Route::post('auth/logout', [AuthController::class, 'logout']);
        Route::post('auth/email/send', [EmailVerificationController::class, 'send'])->middleware('throttle:auth');
        Route::post('auth/email/verify', [EmailVerificationController::class, 'verify'])->middleware('throttle:auth');

        Route::get('menu', [MenuController::class, 'show']);

        Route::middleware('can:'.Permission::OrderCreate->value)->group(function () {
            Route::get('orders', [OrderController::class, 'index']);
            Route::get('orders/{order}', [OrderController::class, 'show']);
            Route::put('orders/{order}', [OrderController::class, 'upsert']); // ID = UUID dari tablet
            Route::post('orders/{order}/pay', [OrderController::class, 'pay']);
            // Kasir boleh memanggil; tanpa izin order.void wajib menyertakan persetujuan PIN owner.
            Route::post('orders/{order}/void', [OrderController::class, 'void']);
        });

        Route::middleware('can:'.Permission::ShiftOperate->value)->group(function () {
            Route::get('shifts/current', [ShiftController::class, 'current']);
            Route::post('shifts/open', [ShiftController::class, 'open']);
            Route::post('shifts/close', [ShiftController::class, 'close']);
        });
        Route::get('shifts', [ShiftController::class, 'index']);

        Route::get('reports/summary', [ReportController::class, 'summary'])
            ->middleware('can:'.Permission::ReportsView->value);

        Route::middleware('can:'.Permission::SettingsManage->value)->group(function () {
            Route::put('settings/receipt', [ReceiptSettingsController::class, 'update']);
            Route::get('settings/features', [FeatureSettingsController::class, 'show']);
            Route::put('settings/features', [FeatureSettingsController::class, 'update']);
            Route::post('devices/current/unregister', DeviceUnregisterController::class);
        });

        Route::middleware('can:'.Permission::MenuManage->value)->group(function () {
            Route::apiResource('categories', CategoryController::class)->only(['store', 'update', 'destroy']);
            Route::post('products/import', ProductImportController::class);
            Route::apiResource('products', ProductController::class)->only(['store', 'update']);
            Route::apiResource('modifier-groups', ModifierGroupController::class)
                ->only(['store', 'update', 'destroy'])
                ->parameters(['modifier-groups' => 'modifierGroup']);
        });
    });
});
