<?php

namespace App\Services;

use App\Enums\Feature;
use App\Models\Device;
use App\Models\Ingredient;
use App\Models\Order;
use App\Models\User;
use App\Support\Audit;
use App\Support\Tenancy\FeatureGate;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Stok bahan & resep (fitur `inventory`). Semua perubahan stok lewat move(): baris bahan dikunci
 * (urut ID, supaya dua transaksi bersamaan tidak saling menunggu), stok & modal rata-rata dihitung
 * ulang, lalu satu baris `stock_movements` dicatat. Stok boleh minus: penjualan tidak pernah
 * ditolak karena stok (pembelian sering terlambat dicatat); minus tampil sebagai peringatan.
 */
class InventoryService
{
    public const UNITS = ['g', 'ml', 'pcs'];

    public const KINDS = [
        'purchase' => 'Pembelian',
        'sale' => 'Terjual',
        'void' => 'Batal (kembali)',
        'waste' => 'Terbuang / rusak',
        'count' => 'Stok opname',
    ];

    public function enabled(): bool
    {
        return app(FeatureGate::class)->enabled(Feature::Inventory);
    }

    /** @return array<string, mixed> */
    public static function present(Ingredient $i): array
    {
        $stock = round((float) $i->stock, 3);

        return [
            'id' => $i->id,
            'name' => $i->name,
            'unit' => $i->unit,
            'stock' => $stock,
            'min_stock' => $i->min_stock === null ? null : round((float) $i->min_stock, 3),
            'avg_cost' => round((float) $i->avg_cost, 4),
            'value' => (int) round(max($stock, 0) * (float) $i->avg_cost),
            'low' => self::isLow($i),
            'active' => $i->active,
        ];
    }

    public static function isLow(Ingredient $i): bool
    {
        return $i->active && ((float) $i->stock < 0 || ($i->min_stock !== null && (float) $i->stock <= (float) $i->min_stock));
    }

    /** @return Collection<int, Ingredient> bahan aktif yang menipis / minus */
    public function lowStock(): Collection
    {
        return Ingredient::query()->where('active', true)->orderBy('name')->get()->filter(fn ($i) => self::isLow($i))->values();
    }

    // ───────────────────────────── resep & HPP ─────────────────────────────

    /** @return array{products: array<string, list<array{ingredient_id: string, qty: float}>>, modifiers: array<string, list<array{ingredient_id: string, qty: float}>>} */
    public function recipes(): array
    {
        $out = ['products' => [], 'modifiers' => []];
        foreach (DB::table('recipe_items')->orderBy('created_at')->get() as $r) {
            $key = $r->product_id !== null ? 'products' : 'modifiers';
            $out[$key][$r->product_id ?? $r->modifier_id][] = ['ingredient_id' => $r->ingredient_id, 'qty' => round((float) $r->qty, 3)];
        }

        return $out;
    }

    /**
     * Ganti seluruh resep satu produk / satu pilihan varian.
     *
     * @param  list<array{ingredient_id: string, qty: float|int|string}>  $items
     */
    public function saveRecipe(string $target, string $id, array $items): void
    {
        $column = $target === 'product' ? 'product_id' : 'modifier_id';
        $table = $target === 'product' ? 'products' : 'modifiers';
        abort_unless(DB::table($table)->where('id', $id)->exists(), 404);

        $ids = array_column($items, 'ingredient_id');
        if (count($ids) !== count(array_unique($ids))) {
            throw ValidationException::withMessages(['items' => 'Bahan yang sama tercantum dua kali.']);
        }
        if (Ingredient::query()->whereIn('id', $ids)->count() !== count($ids)) {
            throw ValidationException::withMessages(['items' => 'Ada bahan yang tidak ditemukan.']);
        }
        foreach ($items as $i => $item) {
            $qty = round((float) $item['qty'], 3);
            if ($qty == 0.0 || ($target === 'product' && $qty < 0)) {
                throw ValidationException::withMessages(["items.{$i}.qty" => $target === 'product'
                    ? 'Jumlah bahan harus lebih dari 0.' : 'Jumlah bahan tidak boleh 0.']);
            }
        }

        $before = DB::table('recipe_items')->where($column, $id)->get(['ingredient_id', 'qty'])
            ->map(fn ($r) => [$r->ingredient_id, round((float) $r->qty, 3)])->all();
        DB::transaction(function () use ($column, $table, $id, $items) {
            DB::table('recipe_items')->where($column, $id)->delete();
            $tenant = app(TenantContext::class)->id();
            foreach ($items as $item) {
                DB::table('recipe_items')->insert([
                    'id' => (string) Str::uuid(), 'tenant_id' => $tenant, $column => $id,
                    'ingredient_id' => $item['ingredient_id'], 'qty' => round((float) $item['qty'], 3),
                    'created_at' => now(), 'updated_at' => now(),
                ]);
            }
            DB::table($table)->where('id', $id)->update(['updated_at' => now()]); // versi menu (HPP owner) berubah
        });
        Audit::record('recipe.saved', null, ['target' => $target, 'id' => $id, 'items' => $before], [
            'target' => $target, 'id' => $id,
            'items' => array_map(fn ($i) => [$i['ingredient_id'], round((float) $i['qty'], 3)], $items),
        ]);
    }

    /**
     * HPP per produk dari resep × modal rata-rata (null = produk tanpa resep).
     *
     * @return array<string, int>
     */
    public function productCosts(): array
    {
        return DB::table('recipe_items')->join('ingredients', 'ingredients.id', '=', 'recipe_items.ingredient_id')
            ->whereNotNull('recipe_items.product_id')->groupBy('recipe_items.product_id')
            ->selectRaw('recipe_items.product_id, sum(recipe_items.qty * ingredients.avg_cost) as cost')
            ->pluck('cost', 'product_id')->map(fn ($c) => max(0, (int) round((float) $c)))->all();
    }

    /** @return array<string, float> tambahan HPP per pilihan varian (boleh negatif) */
    public function modifierCosts(): array
    {
        return DB::table('recipe_items')->join('ingredients', 'ingredients.id', '=', 'recipe_items.ingredient_id')
            ->whereNotNull('recipe_items.modifier_id')->groupBy('recipe_items.modifier_id')
            ->selectRaw('recipe_items.modifier_id, sum(recipe_items.qty * ingredients.avg_cost) as cost')
            ->pluck('cost', 'modifier_id')->map(fn ($c) => (float) $c)->all();
    }

    /**
     * HPP per baris order (salinan ke order_items.unit_cost): resep produk (atau modal manual bila
     * tanpa resep) + resep varian yang dipilih. Null bila produk tanpa resep & tanpa modal manual.
     *
     * @param  list<array<string, mixed>>  $lines  baris dari OrderService::buildLines
     * @return list<array<string, mixed>>
     */
    public function withUnitCosts(array $lines): array
    {
        if (! $this->enabled()) {
            return $lines;
        }
        $products = $this->productCosts();
        $modifiers = $this->modifierCosts();

        return array_map(function (array $line) use ($products, $modifiers) {
            $base = $products[$line['product']->id] ?? $line['product']->cost;
            $extra = array_sum(array_map(fn ($m) => ($modifiers[$m['modifier_id']] ?? 0) * $m['qty'], $line['modifiers']));
            $line['unit_cost'] = $base === null && $extra == 0 ? null : max(0, (int) round(($base ?? 0) + $extra));

            return $line;
        }, $lines);
    }

    // ───────────────────────────── penjualan ─────────────────────────────

    /** Order lunas: potong stok sesuai resep (di transaksi bayar yang sama). */
    public function onPaid(Order $order, User $user): void
    {
        if (! $this->enabled()) {
            return;
        }
        $items = DB::table('order_items')->where('order_id', $order->id)->get(['id', 'product_id', 'qty'])->keyBy('id');
        $mods = DB::table('order_item_modifiers')->whereIn('order_item_id', $items->keys())->whereNotNull('modifier_id')
            ->get(['order_item_id', 'modifier_id', 'qty']);
        $recipes = DB::table('recipe_items')
            ->where(fn ($q) => $q->whereIn('product_id', $items->pluck('product_id')->filter())->orWhereIn('modifier_id', $mods->pluck('modifier_id')))
            ->get();
        if ($recipes->isEmpty()) {
            return;
        }

        $need = [];
        $add = function (string $ingredient, float $qty) use (&$need) {
            $need[$ingredient] = ($need[$ingredient] ?? 0) + $qty;
        };
        foreach ($items as $item) {
            foreach ($recipes->where('product_id', $item->product_id) as $r) {
                $add($r->ingredient_id, (float) $r->qty * $item->qty);
            }
        }
        foreach ($mods as $m) {
            foreach ($recipes->where('modifier_id', $m->modifier_id) as $r) {
                $add($r->ingredient_id, (float) $r->qty * max(1, (int) $m->qty) * $items[$m->order_item_id]->qty);
            }
        }

        $locked = $this->lock(array_keys($need));
        foreach ($need as $id => $qty) {
            if (abs($qty) >= 0.0005) {
                $this->move($locked[$id], 'sale', -$qty, null, ['order_id' => $order->id, 'created_by' => $user->id]);
            }
        }
    }

    /** Order lunas dibatalkan: kembalikan stok yang terpotong (pada modal saat terjual). */
    public function onVoid(Order $order, User $user): void
    {
        $sold = DB::table('stock_movements')->where('order_id', $order->id)->where('kind', 'sale')->get();
        if ($sold->isEmpty() || DB::table('stock_movements')->where('order_id', $order->id)->where('kind', 'void')->exists()) {
            return;
        }
        $locked = $this->lock($sold->pluck('ingredient_id')->all());
        foreach ($sold as $m) {
            $this->move($locked[$m->ingredient_id], 'void', -(float) $m->qty, (float) $m->unit_cost, [
                'order_id' => $order->id, 'created_by' => $user->id,
            ]);
        }
    }

    // ───────────────────────────── stok masuk / keluar ─────────────────────────────

    /**
     * Pembelian dari supplier. Total harga per baris → modal rata-rata bergerak. Bila dibayar dari
     * laci, otomatis tercatat sebagai kas keluar "Beli stok" (bukan biaya: biayanya masuk HPP saat terjual).
     *
     * @param  array{id: string, supplier?: ?string, note?: ?string, paid_from_cash?: bool, lines: list<array{ingredient_id: string, qty: mixed, total_cost: int}>}  $data
     */
    public function purchase(array $data, User $user, Device $device): array
    {
        return $this->batch($data, 'purchase', $user, function (array $locked) use ($data, $user, $device) {
            foreach ($data['lines'] as $line) {
                $qty = round((float) $line['qty'], 3);
                $this->move($locked[$line['ingredient_id']], 'purchase', $qty, (int) $line['total_cost'] / $qty, [
                    'batch_id' => $data['id'], 'supplier' => $data['supplier'] ?? null, 'note' => $data['note'] ?? null,
                    'created_by' => $user->id,
                ]);
            }
            $total = array_sum(array_map(fn ($l) => (int) $l['total_cost'], $data['lines']));
            if (($data['paid_from_cash'] ?? false) && $total > 0) {
                app(CashMovementService::class)->record([
                    'id' => $data['id'], 'kind' => 'out', 'category' => 'stock_purchase', 'amount' => $total,
                    'note' => mb_substr('Beli stok'.(empty($data['supplier']) ? '' : ' · '.$data['supplier']), 0, 120),
                ], $user, $device, internal: true);
            }
            Audit::record('stock.purchase', null, after: [
                'batch_id' => $data['id'], 'supplier' => $data['supplier'] ?? null, 'total' => $total,
                'paid_from_cash' => (bool) ($data['paid_from_cash'] ?? false), 'lines' => count($data['lines']),
            ], user: $user, device: $device);
        });
    }

    /** Bahan terbuang / rusak / tumpah (keluar pada modal rata-rata, dihitung sebagai kerugian). */
    public function waste(array $data, User $user, Device $device): array
    {
        return $this->batch($data, 'waste', $user, function (array $locked) use ($data, $user, $device) {
            foreach ($data['lines'] as $line) {
                $this->move($locked[$line['ingredient_id']], 'waste', -round((float) $line['qty'], 3), null, [
                    'batch_id' => $data['id'], 'note' => $data['note'] ?? null, 'created_by' => $user->id,
                ]);
            }
            Audit::record('stock.waste', null, after: ['batch_id' => $data['id'], 'note' => $data['note'] ?? null,
                'lines' => array_map(fn ($l) => [$l['ingredient_id'], round((float) $l['qty'], 3)], $data['lines'])], user: $user, device: $device);
        });
    }

    /** Stok opname: isi jumlah hasil hitung; selisih dicatat (minus = susut, plus = lebih). */
    public function count(array $data, User $user, Device $device): array
    {
        return $this->batch($data, 'count', $user, function (array $locked) use ($data, $user, $device) {
            $diffs = [];
            foreach ($data['lines'] as $line) {
                $ingredient = $locked[$line['ingredient_id']];
                $diff = round(round((float) $line['counted'], 3) - (float) $ingredient->stock, 3);
                $this->move($ingredient, 'count', $diff, null, [
                    'batch_id' => $data['id'], 'note' => $data['note'] ?? null, 'created_by' => $user->id,
                ]);
                $diffs[] = [$ingredient->name, $diff];
            }
            Audit::record('stock.count', null, after: ['batch_id' => $data['id'], 'diffs' => $diffs], user: $user, device: $device);
        });
    }

    /** @return list<array<string, mixed>> riwayat stok satu bahan (terbaru dulu) */
    public function movements(Ingredient $ingredient, int $limit = 100): array
    {
        return DB::table('stock_movements as m')
            ->leftJoin('users', 'users.id', '=', 'm.created_by')
            ->leftJoin('orders', 'orders.id', '=', 'm.order_id')
            ->where('m.ingredient_id', $ingredient->id)
            ->orderByDesc('m.created_at')->orderByDesc('m.id')->limit($limit)
            ->get(['m.*', 'users.name as user_name', 'orders.number as order_number'])
            ->map(fn ($m) => [
                'id' => $m->id,
                'kind' => $m->kind,
                'kind_label' => self::KINDS[$m->kind] ?? $m->kind,
                'qty' => round((float) $m->qty, 3),
                'balance_after' => round((float) $m->balance_after, 3),
                'unit_cost' => round((float) $m->unit_cost, 4),
                'supplier' => $m->supplier,
                'note' => $m->note,
                'order_number' => $m->order_number,
                'user' => $m->user_name,
                'created_at' => Carbon::parse($m->created_at, 'UTC')->toIso8601String(),
            ])->all();
    }

    // ───────────────────────────── internal ─────────────────────────────

    /** Satu catatan stok (pembelian/terbuang/opname) dengan ID dari tablet: kiriman ulang aman. */
    private function batch(array $data, string $kind, User $user, callable $apply): array
    {
        $ids = array_column($data['lines'], 'ingredient_id');
        if (count($ids) !== count(array_unique($ids))) {
            throw ValidationException::withMessages(['lines' => 'Bahan yang sama tercantum dua kali.']);
        }

        return DB::transaction(function () use ($data, $kind, $ids, $apply) {
            $existing = DB::table('stock_movements')->where('batch_id', $data['id'])->get();
            if ($existing->isNotEmpty()) {
                abort_unless($existing->first()->kind === $kind && $existing->count() === count($ids), 409, 'ID catatan stok sudah dipakai.');

                return ['id' => $data['id'], 'replayed' => true];
            }
            $locked = $this->lock($ids);
            foreach ($ids as $i => $id) {
                if (! isset($locked[$id])) {
                    throw ValidationException::withMessages(["lines.{$i}.ingredient_id" => 'Bahan tidak ditemukan.']);
                }
            }
            $apply($locked);

            return ['id' => $data['id'], 'replayed' => false];
        });
    }

    /** @return array<string, Ingredient> */
    private function lock(array $ids): array
    {
        return Ingredient::query()->whereIn('id', array_unique($ids))->orderBy('id')->lockForUpdate()->get()->keyBy('id')->all();
    }

    /**
     * Ubah stok satu bahan + catat baris buku besar. Masuk dengan harga ($cost) → modal rata-rata
     * bergerak; keluar / masuk tanpa harga → modal tetap.
     */
    private function move(Ingredient $ingredient, string $kind, float $qty, ?float $cost, array $attrs): void
    {
        $stock = (float) $ingredient->stock;
        $avg = (float) $ingredient->avg_cost;
        $newAvg = $avg;
        if ($qty > 0 && $cost !== null) {
            $newAvg = $stock > 0 ? ($stock * $avg + $qty * $cost) / ($stock + $qty) : $cost;
        }
        $newStock = round($stock + $qty, 3);

        $update = ['stock' => $newStock];
        if (round($newAvg, 4) !== round($avg, 4)) {
            $update += ['avg_cost' => round($newAvg, 4), 'updated_at' => now()]; // HPP berubah → versi menu
        }
        DB::table('ingredients')->where('id', $ingredient->id)->update($update);
        $ingredient->forceFill(['stock' => $newStock, 'avg_cost' => round($newAvg, 4)])->syncOriginal();

        DB::table('stock_movements')->insert([
            'id' => (string) Str::uuid(),
            'tenant_id' => $ingredient->tenant_id,
            'ingredient_id' => $ingredient->id,
            'kind' => $kind,
            'qty' => $qty,
            'unit_cost' => round($cost ?? $avg, 4),
            'balance_after' => $newStock,
            'created_at' => now()->format('Y-m-d H:i:s.u'),
            ...$attrs,
        ]);
    }
}
