<?php

use App\Enums\Permission;
use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\DeviceRegistrationController;
use App\Http\Controllers\Api\V1\MenuController;
use App\Http\Controllers\Api\V1\ModifierGroupController;
use App\Http\Controllers\Api\V1\OrderController;
use App\Http\Controllers\Api\V1\ProductController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    // Publik: owner mendaftarkan tablet dengan email + password.
    Route::post('devices/register', DeviceRegistrationController::class)->middleware('throttle:auth');

    // Token perangkat: pilih nama staf lalu login PIN.
    Route::middleware(['auth:sanctum', 'tenant:device'])->group(function () {
        Route::get('auth/staff', [AuthController::class, 'staff']);
        Route::post('auth/pin', [AuthController::class, 'pinLogin'])->middleware('throttle:auth');
    });

    // Token user (hasil login PIN): semua operasi POS.
    Route::middleware(['auth:sanctum', 'tenant:user'])->group(function () {
        Route::get('auth/me', [AuthController::class, 'me']);
        Route::post('auth/logout', [AuthController::class, 'logout']);

        Route::get('menu', [MenuController::class, 'show']);

        Route::middleware('can:'.Permission::OrderCreate->value)->group(function () {
            Route::get('orders', [OrderController::class, 'index']);
            Route::get('orders/{order}', [OrderController::class, 'show']);
            Route::put('orders/{order}', [OrderController::class, 'upsert']); // ID = UUID dari tablet
            Route::post('orders/{order}/pay', [OrderController::class, 'pay']);
        });

        Route::middleware('can:'.Permission::MenuManage->value)->group(function () {
            Route::apiResource('categories', CategoryController::class)->only(['store', 'update', 'destroy']);
            Route::apiResource('products', ProductController::class)->only(['store', 'update']);
            Route::apiResource('modifier-groups', ModifierGroupController::class)
                ->only(['store', 'update', 'destroy'])
                ->parameters(['modifier-groups' => 'modifierGroup']);
        });
    });
});
