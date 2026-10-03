<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Override fitur per tenant di atas default paket (lihat App\Support\Tenancy\FeatureGate).
        Schema::create('tenant_features', function (Blueprint $table) {
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('feature_key');
            $table->foreign('feature_key')->references('key')->on('features')->cascadeOnDelete();
            $table->boolean('enabled');
            $table->jsonb('config')->nullable();
            $table->timestamps();
            $table->primary(['tenant_id', 'feature_key']);
        });

        // Persentase disimpan sebagai basis poin (1000 = 10%) agar tetap integer.
        Schema::create('tenant_settings', function (Blueprint $table) {
            $table->foreignUuid('tenant_id')->primary()->constrained()->cascadeOnDelete();
            $table->string('receipt_name');
            $table->text('receipt_header')->nullable();
            $table->text('receipt_footer')->nullable();
            $table->boolean('tax_enabled')->default(false);
            $table->unsignedInteger('tax_rate_bp')->default(0);
            $table->boolean('service_enabled')->default(false);
            $table->unsignedInteger('service_rate_bp')->default(0);
            $table->unsignedInteger('rounding_unit')->default(0); // 0 = tanpa pembulatan, mis. 100 / 500
            $table->unsignedInteger('cashier_discount_limit_bp')->default(1000);
            $table->timestamps();
        });
        DB::statement('ALTER TABLE tenant_settings ADD CONSTRAINT tenant_settings_rates_check'
            .' CHECK (tax_rate_bp <= 10000 AND service_rate_bp <= 10000 AND cashier_discount_limit_bp <= 10000)');

        Schema::create('audit_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignUuid('device_id')->nullable()->constrained()->nullOnDelete();
            $table->string('action');
            $table->string('entity_type')->nullable();
            $table->uuid('entity_id')->nullable();
            $table->jsonb('before')->nullable();
            $table->jsonb('after')->nullable();
            $table->string('ip', 45)->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index(['tenant_id', 'created_at']);
            $table->index(['tenant_id', 'entity_type', 'entity_id']);
        });

        foreach (['tenant_features', 'tenant_settings', 'audit_logs'] as $t) {
            Rls::enable($t);
        }
        Rls::appendOnly('audit_logs');
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
        Schema::dropIfExists('tenant_settings');
        Schema::dropIfExists('tenant_features');
        DB::statement('DROP FUNCTION IF EXISTS forbid_mutation() CASCADE');
    }
};
