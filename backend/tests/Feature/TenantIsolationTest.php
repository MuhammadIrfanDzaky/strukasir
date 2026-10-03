<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Support\Tenancy\MissingTenantContext;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Bukti isolasi tenant (kompetensi #24, SEC-20 lintas tenant). Dua lapis diuji terpisah:
 * global scope Eloquent dan Row-Level Security PostgreSQL.
 */
class TenantIsolationTest extends TestCase
{
    private object $a;

    private object $b;

    protected function setUp(): void
    {
        parent::setUp();
        $this->a = $this->makeShop('Kedai A');
        $this->b = $this->makeShop('Kedai B');

        $this->tenancy()->run($this->a->tenant->id, fn () => Category::create(['name' => 'Kopi A']));
        $this->tenancy()->run($this->b->tenant->id, fn () => Category::create(['name' => 'Kopi B']));
    }

    public function test_eloquent_only_sees_current_tenant(): void
    {
        $names = $this->tenancy()->run($this->a->tenant->id, fn () => Category::pluck('name')->all());

        $this->assertSame(['Kopi A'], $names);
    }

    public function test_rls_filters_raw_queries_that_bypass_eloquent(): void
    {
        $names = $this->tenancy()->run($this->a->tenant->id,
            fn () => DB::table('categories')->pluck('name')->all());

        $this->assertSame(['Kopi A'], $names);
    }

    public function test_rls_filters_even_when_eloquent_scope_is_removed(): void
    {
        $count = $this->tenancy()->run($this->a->tenant->id,
            fn () => Category::withoutGlobalScopes()->count());

        $this->assertSame(1, $count);
    }

    public function test_query_without_tenant_context_fails_closed(): void
    {
        $this->tenancy()->clear();

        $this->expectException(MissingTenantContext::class);
        Category::query()->get();
    }

    public function test_raw_query_without_tenant_context_sees_nothing(): void
    {
        $this->tenancy()->clear();

        $this->assertSame(0, DB::table('categories')->count());
    }

    public function test_tenant_id_is_taken_from_context_not_from_input(): void
    {
        $category = $this->tenancy()->run($this->a->tenant->id, function () {
            $c = new Category(['name' => 'Coba']);
            $c->tenant_id = $this->b->tenant->id; // upaya menyusup
            $c->save();

            return $c;
        });

        $this->assertSame($this->a->tenant->id, $category->tenant_id);
    }

    public function test_rls_rejects_writing_rows_for_another_tenant(): void
    {
        $this->expectException(QueryException::class);

        $this->tenancy()->run($this->a->tenant->id, fn () => DB::table('categories')->insert([
            'id' => (string) Str::uuid(),
            'tenant_id' => $this->b->tenant->id,
            'name' => 'Selundupan',
        ]));
    }

    public function test_product_cannot_reference_category_of_another_tenant(): void
    {
        $categoryB = $this->tenancy()->bypass(
            fn () => Category::withoutGlobalScopes()->where('name', 'Kopi B')->first());

        $this->expectException(QueryException::class);

        $this->tenancy()->run($this->a->tenant->id, fn () => Product::create([
            'category_id' => $categoryB->id,
            'name' => 'Americano',
            'price' => 13000,
        ]));
    }

    public function test_device_cannot_list_staff_of_another_tenant(): void
    {
        $names = collect($this->api('GET', '/api/v1/auth/staff', $this->a->deviceToken)->assertOk()->json('data'))
            ->pluck('id');

        $this->assertTrue($names->contains($this->a->cashier->id));
        $this->assertFalse($names->contains($this->b->cashier->id));
        $this->assertFalse($names->contains($this->b->owner->id));
    }

    public function test_pin_login_rejects_user_of_another_tenant(): void
    {
        $this->api('POST', '/api/v1/auth/pin', $this->a->deviceToken, [
            'user_id' => $this->b->cashier->id,
            'pin' => self::PIN,
        ])->assertStatus(422);
    }
}
