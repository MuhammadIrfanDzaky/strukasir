<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\DeviceRegistrationController;
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
    });
});
