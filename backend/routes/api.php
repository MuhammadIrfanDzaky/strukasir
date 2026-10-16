<?php

use App\Enums\Permission;
use App\Http\Controllers\Api\V1\AppVersionController;
use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\CustomerController;
use App\Http\Controllers\Api\V1\CustomerImportController;
use App\Http\Controllers\Api\V1\DeviceRegistrationController;
use App\Http\Controllers\Api\V1\DeviceUnregisterController;
use App\Http\Controllers\Api\V1\EmailVerificationController;
use App\Http\Controllers\Api\V1\FeatureSettingsController;
use App\Http\Controllers\Api\V1\InventoryController;
use App\Http\Controllers\Api\V1\LoyaltyController;
use App\Http\Controllers\Api\V1\MayarWebhookController;
use App\Http\Controllers\Api\V1\MenuController;
use App\Http\Controllers\Api\V1\MessageController;
use App\Http\Controllers\Api\V1\ModifierGroupController;
use App\Http\Controllers\Api\V1\OrderController;
use App\Http\Controllers\Api\V1\OutletController;
use App\Http\Controllers\Api\V1\PasswordResetController;
use App\Http\Controllers\Api\V1\ProductController;
use App\Http\Controllers\Api\V1\ProductImportController;
use App\Http\Controllers\Api\V1\ProfileController;
use App\Http\Controllers\Api\V1\PromotionController;
use App\Http\Controllers\Api\V1\ReceiptSettingsController;
use App\Http\Controllers\Api\V1\ReportController;
use App\Http\Controllers\Api\V1\ReportExportController;
use App\Http\Controllers\Api\V1\ShiftController;
use App\Http\Controllers\Api\V1\SignupController;
use App\Http\Controllers\Api\V1\SignupEmailCodeController;
use App\Http\Controllers\Api\V1\SignupOptionsController;
use App\Http\Controllers\Api\V1\StaffController;
use App\Http\Controllers\Api\V1\SubscriptionController;
use App\Http\Controllers\Api\V1\TierController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    Route::get('app/version', AppVersionController::class);

    // Publik: owner mendaftarkan tablet dengan email + password.
    Route::post('devices/register', DeviceRegistrationController::class)->middleware('throttle:auth');
    // Publik: pendaftaran usaha baru (tablet ini otomatis jadi tablet pertama).
    Route::post('signup', SignupController::class)->middleware('throttle:signup');
    Route::get('signup/options', SignupOptionsController::class);
    // Webhook pembayaran paket dari Mayar (token rahasia di URL; status dicek ulang ke API Mayar).
    Route::post('payments/mayar/webhook', MayarWebhookController::class)->middleware('throttle:payment-webhook');
    Route::post('signup/email-code', SignupEmailCodeController::class)->middleware('throttle:auth'); // jenis usaha & wilayah untuk form daftar
    // Publik: lupa password owner (kode 6 digit ke email).
    Route::post('auth/password/forgot', [PasswordResetController::class, 'forgot'])->middleware('throttle:auth');
    Route::post('auth/password/reset', [PasswordResetController::class, 'reset'])->middleware('throttle:auth');

    // Unduhan laporan CSV lewat tautan bertanda tangan (tanpa token; dibuka di browser tablet).
    Route::get('exports/reports', [ReportExportController::class, 'download'])
        ->middleware(['signed:relative', 'throttle:30,1'])->name('reports.export');

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
        // Profil sendiri: nama (& email owner), ganti PIN, ganti password owner.
        Route::put('auth/profile', [ProfileController::class, 'update'])->middleware('throttle:auth');
        Route::put('auth/profile/pin', [ProfileController::class, 'updatePin'])->middleware('throttle:auth');
        Route::put('auth/profile/password', [ProfileController::class, 'updatePassword'])->middleware('throttle:auth');

        Route::get('menu', [MenuController::class, 'show']);
        Route::get('subscription', [SubscriptionController::class, 'show']);
        Route::post('subscription/checkout', [SubscriptionController::class, 'checkout'])
            ->middleware(['can:'.Permission::UsersManage->value, 'throttle:10,1']);
        Route::get('subscription/invoices/{invoice}', [SubscriptionController::class, 'invoice'])
            ->whereUuid('invoice')->middleware('can:'.Permission::UsersManage->value);
        Route::post('subscription/request', [SubscriptionController::class, 'request'])
            ->middleware('can:'.Permission::UsersManage->value);

        Route::middleware('can:'.Permission::OrderCreate->value)->group(function () {
            Route::get('orders', [OrderController::class, 'index']);
            Route::get('orders/{order}', [OrderController::class, 'show']);
            Route::put('orders/{order}', [OrderController::class, 'upsert'])->middleware('plan.active'); // ID = UUID dari tablet
            Route::post('orders/{order}/pay', [OrderController::class, 'pay'])->middleware('plan.active');
            // Kasir boleh memanggil; tanpa izin order.void wajib menyertakan persetujuan PIN owner.
            Route::post('orders/{order}/void', [OrderController::class, 'void']);
            Route::get('vouchers/check', [PromotionController::class, 'check'])->middleware('throttle:30,1');
        });

        // Pelanggan / member (fitur `customers`): kasir mencari & mendaftarkan, owner mengelola.
        Route::middleware('can:'.Permission::CustomersView->value)->group(function () {
            Route::get('customers', [CustomerController::class, 'index']);
            Route::post('customers', [CustomerController::class, 'store']);
        });
        // Pelunasan kasbon: kasir yang mengoperasikan shift (uang masuk laci).
        // Pesan WhatsApp: kasir boleh struk digital (dicek di controller), sisanya owner.
        Route::post('customers/{customer}/messages', [MessageController::class, 'prepare'])
            ->middleware('can:'.Permission::CustomersView->value);
        Route::post('customers/{customer}/credit-repayments', [CustomerController::class, 'repayCredit'])
            ->middleware(['can:'.Permission::CustomersView->value, 'can:'.Permission::ShiftOperate->value]);
        Route::middleware('can:'.Permission::CustomersManage->value)->group(function () {
            Route::post('customers/import', CustomerImportController::class);
            Route::get('customers/{customer}', [CustomerController::class, 'show']);
            Route::put('customers/{customer}', [CustomerController::class, 'update']);
            Route::post('customers/{customer}/anonymize', [CustomerController::class, 'anonymize']);
            Route::post('customers/{customer}/loyalty-adjust', [CustomerController::class, 'adjustLoyalty']);
            Route::put('customers/{customer}/tier', [CustomerController::class, 'setTier']);
            Route::get('messages/audience', [MessageController::class, 'audience']);
            Route::put('customers/{customer}/credit-limit', [CustomerController::class, 'setCreditLimit']);
            Route::post('customers/{customer}/credit-repayments/{repayment}/reverse', [CustomerController::class, 'reverseRepayment'])->whereUuid('repayment');
        });

        Route::middleware('can:'.Permission::ShiftOperate->value)->group(function () {
            Route::get('shifts/current', [ShiftController::class, 'current']);
            Route::post('shifts/open', [ShiftController::class, 'open'])->middleware('plan.active');
            Route::post('shifts/close', [ShiftController::class, 'close']);
            // Kas keluar / masuk di luar penjualan (pembatalan: kasir butuh PIN owner).
            Route::get('shifts/current/cash-movements', [ShiftController::class, 'cashMovements']);
            Route::get('shifts/{shift}/report', [ShiftController::class, 'report'])->whereUuid('shift');
            Route::post('shifts/current/cash-movements', [ShiftController::class, 'recordCashMovement']);
            Route::post('cash-movements/{movement}/cancel', [ShiftController::class, 'cancelCashMovement'])->whereUuid('movement');
        });
        Route::get('shifts', [ShiftController::class, 'index']);

        Route::get('reports/summary', [ReportController::class, 'summary'])
            ->middleware('can:'.Permission::ReportsView->value);
        Route::post('reports/export-link', [ReportExportController::class, 'link'])
            ->middleware('can:'.Permission::ReportsView->value);

        Route::middleware('can:'.Permission::SettingsManage->value)->group(function () {
            Route::put('settings/receipt', [ReceiptSettingsController::class, 'update']);
            Route::get('settings/features', [FeatureSettingsController::class, 'show']);
            Route::put('settings/features', [FeatureSettingsController::class, 'update']);
            Route::get('settings/loyalty', [LoyaltyController::class, 'show']);
            Route::put('settings/loyalty', [LoyaltyController::class, 'update']);
            Route::get('settings/tiers', [TierController::class, 'show']);
            Route::put('settings/tiers', [TierController::class, 'update']);
            Route::get('settings/promotions', [PromotionController::class, 'index']);
            Route::post('promotions', [PromotionController::class, 'savePromotion']);
            Route::put('promotions/{promotion}', [PromotionController::class, 'savePromotion']);
            Route::post('vouchers', [PromotionController::class, 'saveVoucher']);
            Route::put('vouchers/{voucher}', [PromotionController::class, 'saveVoucher']);
            Route::get('settings/messages', [MessageController::class, 'templates']);
            Route::put('settings/messages', [MessageController::class, 'saveTemplates']);
            Route::post('devices/current/unregister', DeviceUnregisterController::class);
            // Outlet (fitur `multi_outlet` untuk outlet kedua dst.).
            Route::get('outlets', [OutletController::class, 'index']);
            Route::post('outlets', [OutletController::class, 'save']);
            Route::put('outlets/{outlet}', [OutletController::class, 'save'])->whereUuid('outlet');
            Route::put('devices/{device}/outlet', [OutletController::class, 'moveDevice'])->whereUuid('device');
            Route::post('devices/{device}/revoke', [DeviceUnregisterController::class, 'other'])->whereUuid('device');
        });

        // Pegawai (owner): tambah kasir, ganti nama, reset PIN, nonaktifkan.
        Route::middleware('can:'.Permission::UsersManage->value)->group(function () {
            Route::get('staff', [StaffController::class, 'index']);
            Route::post('staff', [StaffController::class, 'store']);
            Route::put('staff/{staff}', [StaffController::class, 'update'])->whereUuid('staff');
            Route::post('staff/{staff}/pin', [StaffController::class, 'resetPin'])->whereUuid('staff');
        });

        // Stok bahan & resep (fitur `inventory`).
        Route::middleware('can:'.Permission::InventoryManage->value)->group(function () {
            Route::get('inventory', [InventoryController::class, 'index']);
            Route::post('ingredients', [InventoryController::class, 'saveIngredient']);
            Route::put('ingredients/{ingredient}', [InventoryController::class, 'saveIngredient'])->whereUuid('ingredient');
            Route::get('ingredients/{ingredient}/movements', [InventoryController::class, 'movements'])->whereUuid('ingredient');
            Route::post('stock/purchases', [InventoryController::class, 'purchase']);
            Route::post('stock/waste', [InventoryController::class, 'waste']);
            Route::post('stock/counts', [InventoryController::class, 'count']);
            Route::put('recipes/{target}/{id}', [InventoryController::class, 'saveRecipe'])->whereIn('target', ['product', 'modifier'])->whereUuid('id');
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
