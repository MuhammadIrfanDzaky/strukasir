<?php

use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Jenis pesanan per order (Takeaway / Dine-in) menggantikan pertanyaan "cara berjualan" saat daftar.
 * - tenant_settings.order_types_enabled: pilihan Takeaway | Dine-in tampil di kasir
 * - tenant_settings.default_order_type: pilihan awal tiap order baru
 * - orders.order_type (null = fitur mati / order lama), orders.table_label (nomor meja, dine-in)
 * Service charge hanya untuk dine-in bila fitur ini aktif.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->boolean('order_types_enabled')->default(false);
            $table->string('default_order_type', 10)->default('takeaway');
        });
        DB::statement("ALTER TABLE tenant_settings ADD CONSTRAINT tenant_settings_default_order_type_check CHECK (default_order_type IN ('takeaway', 'dine_in'))");

        Schema::table('orders', function (Blueprint $table) {
            $table->string('order_type', 10)->nullable();
            $table->string('table_label', 20)->nullable();
        });
        DB::statement("ALTER TABLE orders ADD CONSTRAINT orders_order_type_check CHECK (order_type IS NULL OR order_type IN ('takeaway', 'dine_in'))");

        // Kedai makan yang melayani makan di tempat (atau kedai lama tanpa profil, seperti BerryBrew):
        // aktif, sesuai cara berjualan yang dulu dipilih saat daftar.
        app(TenantContext::class)->bypass(fn () => DB::statement(<<<'SQL'
            UPDATE tenant_settings s
            SET order_types_enabled = true,
                default_order_type = CASE WHEN t.sales_mode = 'dine_in' OR t.sector = 'restaurant' THEN 'dine_in' ELSE 'takeaway' END
            FROM tenants t
            WHERE t.id = s.tenant_id
              AND (t.sector IS NULL OR (t.sector IN ('coffee_shop', 'restaurant', 'street_food', 'bakery', 'beverage')
                   AND (t.sales_mode IS NULL OR t.sales_mode <> 'takeaway')))
            SQL));
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE orders DROP CONSTRAINT orders_order_type_check');
        Schema::table('orders', fn (Blueprint $table) => $table->dropColumn(['order_type', 'table_label']));
        DB::statement('ALTER TABLE tenant_settings DROP CONSTRAINT tenant_settings_default_order_type_check');
        Schema::table('tenant_settings', fn (Blueprint $table) => $table->dropColumn(['order_types_enabled', 'default_order_type']));
    }
};
