<?php

namespace Database\Seeders;

use App\Models\Category;
use App\Models\Modifier;
use App\Models\ModifierGroup;
use App\Models\Product;
use App\Models\Tenant;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Seeder;

/**
 * Menu asli Kedai Kopi BerryBrew (papan menu di kedai, Okt 2026) untuk tenant `berrybrew` di development.
 * Aman dijalankan berulang: produk/kategori/grup dicocokkan dari nama lalu diperbarui; produk lama yang
 * tidak ada di menu dinonaktifkan (bukan dihapus, supaya riwayat order tetap utuh).
 *
 * Harga Hot/Cold: harga dasar = Hot, pilihan "Cold" menambah selisihnya. Menu yang hanya Cold atau
 * hanya Hot tidak memakai grup Suhu (harga langsung).
 *
 *   php artisan db:seed --class=BerryBrewMenuSeeder
 */
class BerryBrewMenuSeeder extends Seeder
{
    public function run(TenantContext $context): void
    {
        $tenant = Tenant::where('code', 'berrybrew')->first();
        if ($tenant === null) {
            $this->command?->warn('Tenant berrybrew belum ada; jalankan DatabaseSeeder dulu.');

            return;
        }

        $context->run($tenant->id, fn () => $this->seedMenu());
        $this->command?->info('Menu asli BerryBrew diterapkan.');
    }

    public function seedMenu(): void
    {
        $suhu = $this->group('Suhu', 1, 1, 0, [['Hot', 0], ['Cold', 2000]]);
        $suhuSanger = $this->group('Suhu Sanger', 1, 1, 1, [['Hot', 0], ['Cold', 3000]]);
        $gula = $this->group('Gula', 0, 1, 2, [['Less sugar', 0], ['No sugar', 0]]);
        // Additional: Extra Shot 5K, boleh lebih dari 1 (mis. 2 extra shot).
        $tambahan = $this->group('Tambahan', 0, 3, 3, [['Extra shot', 5000]], allowQuantity: true, maxQuantity: 3);

        $this->renameCategory('Kopi', 'Coffee');
        $this->renameCategory('Non Kopi', 'Non Coffee');
        $coffee = $this->category('Coffee', 0);
        $nonCoffee = $this->category('Non Coffee', 1);
        $manual = $this->category('Manual Brew', 2);
        $snacks = $this->category('Snacks', 3);

        $hotCold = [$suhu, $gula, $tambahan];
        $coldCoffee = [$gula, $tambahan];

        // [kategori, nama, harga (Hot bila ada), grup pilihan]
        $menu = [
            [$coffee, 'Espresso', 10000, [$tambahan]],
            [$coffee, 'Americano', 13000, $hotCold],
            [$coffee, 'Sanger', 15000, [$suhuSanger, $gula, $tambahan]],
            [$coffee, 'Kopi Susu Aren', 15000, $coldCoffee],
            [$coffee, 'Cafe Latte', 20000, $hotCold],
            [$coffee, 'Cappuccino', 20000, $hotCold],
            [$coffee, 'Peach Americano', 22000, $coldCoffee],
            [$coffee, 'Orange Americano', 22000, $coldCoffee],
            [$coffee, 'Mocha', 22000, $hotCold],
            [$coffee, 'Berrycano', 22000, $coldCoffee],
            [$coffee, 'Hazelnut Latte', 20000, $hotCold],

            [$nonCoffee, 'Matcha Latte', 20000, [$gula]],
            [$nonCoffee, 'Matcha Berry Latte', 24000, [$gula]],
            [$nonCoffee, 'Matcha Espresso', 22000, [$gula, $tambahan]],
            [$nonCoffee, 'Lemon Tea', 13000, [$suhu, $gula]],
            [$nonCoffee, 'Thai Tea', 15000, [$gula]],
            [$nonCoffee, 'Chocolate', 18000, [$suhu, $gula]],
            [$nonCoffee, 'Peach Tea', 15000, [$suhu, $gula]],

            [$manual, 'Beans Local', 25000, []],
            [$manual, 'International', 30000, []],

            [$snacks, 'Tortilla', 20000, []],
            [$snacks, 'Kentang Goreng', 20000, []],
            [$snacks, 'Roti', 4000, []],
            [$snacks, 'Peyek', 5000, []],
            [$snacks, 'Air Mineral', 6000, []],
        ];

        $keep = [];
        foreach ($menu as $sort => [$category, $name, $price, $groups]) {
            $product = Product::query()->whereRaw('lower(name) = ?', [strtolower($name)])->first() ?? new Product;
            $product->fill([
                'category_id' => $category->id, 'name' => $name, 'price' => $price, 'sort' => $sort, 'active' => true,
            ]);
            $product->sold_out = false;
            $product->save();
            $product->modifierGroups()->sync(collect($groups)->values()->mapWithKeys(
                fn (ModifierGroup $g, int $i) => [$g->id => ['tenant_id' => $product->tenant_id, 'sort' => $i]],
            )->all());
            $keep[] = $product->id;
        }

        Product::query()->whereNotIn('id', $keep)->update(['active' => false]);
        // Kategori tanpa produk aktif disembunyikan dari kasir.
        Category::query()->whereNotIn('id', [$coffee->id, $nonCoffee->id, $manual->id, $snacks->id])->update(['active' => false]);
    }

    private function category(string $name, int $sort): Category
    {
        $category = Category::query()->where('name', $name)->first() ?? new Category(['name' => $name]);
        $category->fill(['sort' => $sort, 'active' => true])->save();

        return $category;
    }

    private function renameCategory(string $from, string $to): void
    {
        if (! Category::query()->where('name', $to)->exists()) {
            Category::query()->where('name', $from)->update(['name' => $to]);
        }
    }

    /** @param  list<array{0: string, 1: int}>  $options  [nama, tambahan harga]; opsi lain di grup dinonaktifkan */
    private function group(string $name, int $min, int $max, int $sort, array $options, bool $allowQuantity = false, int $maxQuantity = 1): ModifierGroup
    {
        $group = ModifierGroup::query()->where('name', $name)->first() ?? new ModifierGroup(['name' => $name]);
        $group->fill([
            'min_select' => $min, 'max_select' => $max, 'sort' => $sort,
            'allow_quantity' => $allowQuantity, 'max_quantity' => $maxQuantity,
        ])->save();

        $keep = [];
        foreach ($options as $i => [$optionName, $delta]) {
            $modifier = $group->modifiers()->where('name', $optionName)->first() ?? new Modifier(['name' => $optionName]);
            $modifier->fill(['price_delta' => $delta, 'sort' => $i, 'active' => true]);
            $modifier->modifier_group_id = $group->id;
            $modifier->save();
            $keep[] = $modifier->id;
        }
        $group->modifiers()->whereNotIn('id', $keep)->update(['active' => false]);

        return $group;
    }
}
