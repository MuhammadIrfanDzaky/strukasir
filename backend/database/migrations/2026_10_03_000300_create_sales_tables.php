<?php

use App\Support\Database\Rls;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Semua nominal = integer rupiah. Kolom `currency` disimpan eksplisit walau saat ini selalu IDR.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('shifts', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('device_id');
            $table->uuid('opened_by');
            $table->foreign(['tenant_id', 'opened_by'])->references(['tenant_id', 'id'])->on('users');
            $table->timestamp('opened_at');
            $table->unsignedBigInteger('opening_cash');
            $table->uuid('closed_by')->nullable();
            $table->foreign(['tenant_id', 'closed_by'])->references(['tenant_id', 'id'])->on('users');
            $table->timestamp('closed_at')->nullable();
            $table->unsignedBigInteger('expected_cash')->nullable();
            $table->unsignedBigInteger('counted_cash')->nullable();
            $table->bigInteger('difference')->nullable();
            $table->text('note')->nullable();
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->index(['tenant_id', 'opened_at']);
            $table->foreign(['tenant_id', 'device_id'])->references(['tenant_id', 'id'])->on('devices');
        });
        // Satu tablet hanya boleh punya satu shift terbuka.
        DB::statement('CREATE UNIQUE INDEX shifts_one_open_per_device ON shifts (device_id) WHERE closed_at IS NULL');

        // Penghitung nomor order per tenant per hari bisnis (dikunci dengan SELECT ... FOR UPDATE).
        Schema::create('order_counters', function (Blueprint $table) {
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->date('business_date');
            $table->unsignedInteger('last_number')->default(0);
            $table->primary(['tenant_id', 'business_date']);
        });

        Schema::create('orders', function (Blueprint $table) {
            $table->uuid('id')->primary(); // dibuat di tablet = idempotency key
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('device_id');
            $table->uuid('shift_id')->nullable();
            $table->uuid('cashier_id');
            $table->foreign(['tenant_id', 'cashier_id'])->references(['tenant_id', 'id'])->on('users');
            $table->date('business_date');
            $table->string('number');
            $table->string('status')->default('open');
            $table->string('customer_label')->nullable();
            $table->char('currency', 3)->default('IDR');
            $table->unsignedBigInteger('subtotal')->default(0);
            $table->string('order_discount_type')->nullable(); // amount | percent
            $table->unsignedBigInteger('order_discount_value')->default(0); // rupiah atau basis poin
            $table->unsignedBigInteger('discount_total')->default(0);
            $table->unsignedBigInteger('service_total')->default(0);
            $table->unsignedBigInteger('tax_total')->default(0);
            $table->bigInteger('rounding')->default(0);
            $table->unsignedBigInteger('grand_total')->default(0);
            $table->unsignedBigInteger('paid_total')->default(0);
            $table->unsignedBigInteger('change_total')->default(0);
            $table->timestamp('client_created_at')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->timestamp('voided_at')->nullable();
            $table->uuid('voided_by')->nullable();
            $table->foreign(['tenant_id', 'voided_by'])->references(['tenant_id', 'id'])->on('users');
            $table->text('void_reason')->nullable();
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->unique(['tenant_id', 'business_date', 'number']);
            $table->index(['tenant_id', 'status', 'created_at']);
            $table->index(['tenant_id', 'shift_id']);
            $table->foreign(['tenant_id', 'device_id'])->references(['tenant_id', 'id'])->on('devices');
            $table->foreign(['tenant_id', 'shift_id'])->references(['tenant_id', 'id'])->on('shifts');
        });
        DB::statement("ALTER TABLE orders ADD CONSTRAINT orders_status_check CHECK (status IN ('open', 'paid', 'void'))");
        DB::statement("ALTER TABLE orders ADD CONSTRAINT orders_discount_type_check CHECK (order_discount_type IS NULL OR order_discount_type IN ('amount', 'percent'))");
        DB::statement('ALTER TABLE orders ADD CONSTRAINT orders_void_reason_check CHECK (status <> \'void\' OR (void_reason IS NOT NULL AND voided_by IS NOT NULL))');

        // Status hanya boleh maju: open → paid, open → void, paid → void. Tidak pernah mundur.
        DB::statement(<<<'SQL'
            CREATE OR REPLACE FUNCTION order_status_guard() RETURNS trigger AS $$
            BEGIN
                IF NEW.status = OLD.status THEN
                    IF OLD.status <> 'open' AND current_setting('app.allow_purge', true) IS DISTINCT FROM 'on' THEN
                        -- Order final (paid/void) hanya boleh berubah lewat transisi status.
                        IF NEW.grand_total <> OLD.grand_total OR NEW.paid_total <> OLD.paid_total THEN
                            RAISE EXCEPTION 'order % is final (%)', OLD.id, OLD.status;
                        END IF;
                    END IF;
                    RETURN NEW;
                END IF;
                IF (OLD.status = 'open' AND NEW.status IN ('paid', 'void'))
                   OR (OLD.status = 'paid' AND NEW.status = 'void') THEN
                    RETURN NEW;
                END IF;
                RAISE EXCEPTION 'invalid order status transition % -> %', OLD.status, NEW.status;
            END;
            $$ LANGUAGE plpgsql
        SQL);
        DB::statement('CREATE TRIGGER orders_status_guard BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION order_status_guard()');

        Schema::create('order_items', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('order_id');
            $table->uuid('product_id')->nullable(); // referensi lunak; snapshot di bawah yang berlaku
            $table->string('name');
            $table->unsignedBigInteger('unit_price');
            $table->unsignedInteger('qty');
            $table->unsignedBigInteger('modifiers_total')->default(0); // per unit
            $table->string('discount_type')->nullable();
            $table->unsignedBigInteger('discount_value')->default(0);
            $table->unsignedBigInteger('discount_total')->default(0);
            $table->unsignedBigInteger('line_total');
            $table->text('note')->nullable();
            $table->unsignedInteger('sort')->default(0);
            $table->timestamps();

            $table->unique(['tenant_id', 'id']);
            $table->index(['tenant_id', 'order_id']);
            $table->index(['tenant_id', 'product_id']);
            $table->foreign(['tenant_id', 'order_id'])->references(['tenant_id', 'id'])->on('orders')->cascadeOnDelete();
        });
        DB::statement('ALTER TABLE order_items ADD CONSTRAINT order_items_qty_check CHECK (qty > 0)');

        Schema::create('order_item_modifiers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('order_item_id');
            $table->uuid('modifier_id')->nullable();
            $table->string('group_name');
            $table->string('name');
            $table->unsignedBigInteger('price_delta')->default(0);

            $table->index(['tenant_id', 'order_item_id']);
            $table->foreign(['tenant_id', 'order_item_id'])->references(['tenant_id', 'id'])
                ->on('order_items')->cascadeOnDelete();
        });

        Schema::create('payments', function (Blueprint $table) {
            $table->uuid('id')->primary(); // dibuat di tablet = idempotency key
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->uuid('order_id');
            $table->uuid('shift_id')->nullable();
            $table->string('kind')->default('payment'); // payment | refund (refund = baris baru, bukan edit)
            $table->string('method');
            $table->char('currency', 3)->default('IDR');
            $table->unsignedBigInteger('amount');
            $table->unsignedBigInteger('tendered')->nullable(); // uang diterima (cash)
            $table->unsignedBigInteger('change')->default(0);
            $table->string('reference')->nullable();
            $table->uuid('confirmed_by');
            $table->foreign(['tenant_id', 'confirmed_by'])->references(['tenant_id', 'id'])->on('users');
            $table->timestamp('confirmed_at');
            $table->timestamp('created_at')->useCurrent();

            $table->index(['tenant_id', 'order_id']);
            $table->index(['tenant_id', 'shift_id', 'method']);
            $table->index(['tenant_id', 'confirmed_at']);
            $table->foreign(['tenant_id', 'order_id'])->references(['tenant_id', 'id'])->on('orders');
            $table->foreign(['tenant_id', 'shift_id'])->references(['tenant_id', 'id'])->on('shifts');
        });
        DB::statement("ALTER TABLE payments ADD CONSTRAINT payments_kind_check CHECK (kind IN ('payment', 'refund'))");
        DB::statement("ALTER TABLE payments ADD CONSTRAINT payments_method_check CHECK (method IN ('cash', 'debit', 'qris'))");
        DB::statement('ALTER TABLE payments ADD CONSTRAINT payments_amount_check CHECK (amount > 0)');
        DB::statement("ALTER TABLE payments ADD CONSTRAINT payments_cash_check CHECK (method = 'cash' OR (tendered IS NULL AND change = 0))");

        foreach (['shifts', 'order_counters', 'orders', 'order_items', 'order_item_modifiers', 'payments'] as $t) {
            Rls::enable($t);
        }
        Rls::appendOnly('payments');
    }

    public function down(): void
    {
        Schema::dropIfExists('payments');
        Schema::dropIfExists('order_item_modifiers');
        Schema::dropIfExists('order_items');
        Schema::dropIfExists('orders');
        DB::statement('DROP FUNCTION IF EXISTS order_status_guard() CASCADE');
        Schema::dropIfExists('order_counters');
        Schema::dropIfExists('shifts');
    }
};
