<?php

namespace App\Services;

use App\Http\Requests\ProductRequest;
use App\Models\Category;
use App\Models\Product;
use App\Support\Audit;
use Illuminate\Support\Facades\DB;

/**
 * Import produk dari CSV (mis. hasil export POS lama). Semua-atau-tidak-sama-sekali: bila ada
 * satu baris salah, tidak ada yang disimpan dan semua kesalahan dilaporkan per baris.
 *
 * Kolom dikenali dari nama header (tanpa beda huruf besar/kecil): kode, nama, kategori,
 * harga jual, modal / harga dasar / HPP, aktif, favorit. Pemisah koma atau titik-koma.
 * Produk dicocokkan lewat kode (bila ada), lalu lewat nama; yang belum ada dibuat baru.
 */
class ProductImportService
{
    public const MAX_ROWS = 1000;

    private const ALIASES = [
        'code' => ['kode', 'kode produk', 'kodeproduk', 'sku', 'code', 'product code'],
        'name' => ['nama', 'nama produk', 'namaproduk', 'produk', 'name', 'product', 'product name'],
        'category' => ['kategori', 'kategori produk', 'category'],
        'price' => ['harga', 'harga jual', 'hargajual', 'price', 'selling price'],
        'cost' => ['modal', 'harga modal', 'harga dasar', 'harga dasar (hpp / modal)', 'hpp', 'cost', 'harga pokok'],
        'active' => ['aktif', 'status', 'active'],
        'favorite' => ['favorit', 'produk favorit', 'favorite'],
    ];

    /**
     * @return array{created:int, updated:int, categories_created:list<string>, errors:list<array{row:int, message:string}>, saved:bool}
     */
    public function import(string $csv, bool $dryRun): array
    {
        $rows = $this->parse($csv, $errors);
        $plan = $errors === [] ? $this->plan($rows, $errors) : null;

        $result = [
            'created' => 0,
            'updated' => 0,
            'categories_created' => [],
            'errors' => $errors,
            'saved' => false,
        ];
        if ($plan === null || $errors !== []) {
            $result['errors'] = $errors;

            return $result;
        }

        $result['created'] = count(array_filter($plan['products'], fn ($p) => $p['product'] === null));
        $result['updated'] = count($plan['products']) - $result['created'];
        $result['categories_created'] = array_values($plan['new_categories']);
        if ($dryRun) {
            return $result;
        }

        DB::transaction(function () use ($plan) {
            $categories = Category::query()->get()->keyBy(fn (Category $c) => mb_strtolower($c->name));
            $sort = (int) Category::query()->max('sort');
            foreach ($plan['new_categories'] as $key => $name) {
                $categories[$key] = Category::create(['name' => $name, 'active' => true, 'sort' => ++$sort]);
            }

            $productSort = (int) Product::query()->max('sort');
            foreach ($plan['products'] as $p) {
                $product = $p['product'] ?? new Product(['sort' => ++$productSort, 'active' => true]);
                $product->fill(['category_id' => $categories[$p['category_key']]->id, ...$p['fields']]);
                $product->save();
            }
        });

        Audit::record('product.imported', null, after: [
            'created' => $result['created'],
            'updated' => $result['updated'],
            'categories_created' => $result['categories_created'],
        ]);
        $result['saved'] = true;

        return $result;
    }

    /** @return list<array<string, string>> baris dengan kunci kolom kanonik; `_row` = nomor baris di file */
    private function parse(string $csv, ?array &$errors): array
    {
        $errors = [];
        $csv = preg_replace('/^\xEF\xBB\xBF/', '', str_replace(["\r\n", "\r"], "\n", $csv));
        $lines = array_values(array_filter(explode("\n", $csv), fn ($l) => trim($l) !== ''));
        if (count($lines) < 2) {
            $errors[] = ['row' => 1, 'message' => 'File kosong atau hanya berisi judul kolom.'];

            return [];
        }
        if (count($lines) - 1 > self::MAX_ROWS) {
            $errors[] = ['row' => 1, 'message' => 'Maksimal '.self::MAX_ROWS.' produk per import.'];

            return [];
        }

        $delimiter = substr_count($lines[0], ';') > substr_count($lines[0], ',') ? ';' : ',';
        $columns = [];
        foreach (str_getcsv($lines[0], $delimiter, '"', '') as $i => $header) {
            $key = $this->column($header);
            if ($key !== null && ! in_array($key, $columns, true)) {
                $columns[$i] = $key;
            }
        }
        foreach (['name' => 'Nama produk', 'price' => 'Harga jual'] as $required => $label) {
            if (! in_array($required, $columns, true)) {
                $errors[] = ['row' => 1, 'message' => "Kolom \"{$label}\" tidak ditemukan di judul kolom."];
            }
        }
        if ($errors !== []) {
            return [];
        }

        $rows = [];
        foreach (array_slice($lines, 1) as $n => $line) {
            $cells = str_getcsv($line, $delimiter, '"', '');
            $row = ['_row' => (string) ($n + 2)];
            foreach ($columns as $i => $key) {
                $row[$key] = trim((string) ($cells[$i] ?? ''));
            }
            $rows[] = $row;
        }

        return $rows;
    }

    private function column(string $header): ?string
    {
        $h = mb_strtolower(trim(preg_replace('/\s+/', ' ', $header)));
        $h = trim($h, " *\t");
        foreach (self::ALIASES as $key => $names) {
            if (in_array($h, $names, true)) {
                return $key;
            }
        }

        return null;
    }

    /**
     * Validasi + cocokkan dengan data yang ada. Tidak menyimpan apa pun.
     *
     * @param  list<array<string,string>>  $rows
     * @return array{products: list<array{product: ?Product, category_key: string, fields: array<string,mixed>}>, new_categories: array<string,string>}
     */
    private function plan(array $rows, array &$errors): array
    {
        $byCode = Product::query()->whereNotNull('code')->get()->keyBy(fn (Product $p) => mb_strtolower($p->code));
        $byName = Product::query()->get()->groupBy(fn (Product $p) => mb_strtolower($p->name));
        $categories = Category::query()->pluck('name')->mapWithKeys(fn ($n) => [mb_strtolower($n) => $n]);

        $plan = ['products' => [], 'new_categories' => []];
        $seenCodes = [];
        $seenProducts = [];

        foreach ($rows as $row) {
            $line = (int) $row['_row'];
            $fail = function (string $message) use (&$errors, $line) {
                $errors[] = ['row' => $line, 'message' => $message];
            };

            $name = mb_substr($row['name'] ?? '', 0, 80);
            if ($name === '') {
                $fail('Nama produk kosong.');

                continue;
            }
            $price = $this->money($row['price'] ?? '');
            if ($price === null || $price > ProductRequest::MAX_PRICE) {
                $fail("Harga jual \"{$row['price']}\" tidak valid.");

                continue;
            }
            $fields = ['name' => $name, 'price' => $price];

            if (($row['cost'] ?? '') !== '') {
                $cost = $this->money($row['cost']);
                if ($cost === null || $cost > ProductRequest::MAX_PRICE) {
                    $fail("Modal \"{$row['cost']}\" tidak valid.");

                    continue;
                }
                $fields['cost'] = $cost;
            }

            $code = $row['code'] ?? '';
            if ($code !== '') {
                if (! preg_match(ProductRequest::CODE_PATTERN, $code)) {
                    $fail("Kode \"{$code}\" hanya boleh huruf, angka, titik, minus, garis bawah (maks. 30).");

                    continue;
                }
                $key = mb_strtolower($code);
                if (isset($seenCodes[$key])) {
                    $fail("Kode \"{$code}\" dobel (juga di baris {$seenCodes[$key]}).");

                    continue;
                }
                $seenCodes[$key] = $line;
                $fields['code'] = $code;
            }

            foreach (['active', 'favorite'] as $flag) {
                if (($row[$flag] ?? '') !== '') {
                    $value = $this->bool($row[$flag]);
                    if ($value === null) {
                        $fail("Nilai \"{$row[$flag]}\" untuk kolom {$flag} tidak dikenali (pakai ya/tidak).");

                        continue 2;
                    }
                    $fields[$flag] = $value;
                }
            }

            $categoryName = mb_substr(($row['category'] ?? '') !== '' ? $row['category'] : 'Lainnya', 0, 60);
            $categoryKey = mb_strtolower($categoryName);
            if (! isset($categories[$categoryKey])) {
                $plan['new_categories'][$categoryKey] ??= $categoryName;
            }

            // Cocokkan: kode dulu, lalu nama (hanya bila namanya unik di kedai).
            $product = $code !== '' ? ($byCode[mb_strtolower($code)] ?? null) : null;
            if ($product === null) {
                $sameName = $byName[mb_strtolower($name)] ?? collect();
                $product = $sameName->count() === 1 ? $sameName->first() : null;
                if ($product !== null && $code !== '' && $product->code !== null && mb_strtolower($product->code) !== mb_strtolower($code)) {
                    $product = null; // nama sama tapi kode berbeda → produk lain
                }
            }
            if ($product !== null) {
                if (isset($seenProducts[$product->id])) {
                    $fail("Produk \"{$name}\" muncul dua kali (juga di baris {$seenProducts[$product->id]}).");

                    continue;
                }
                $seenProducts[$product->id] = $line;
                // Kode baru tidak boleh bentrok dengan produk lain yang sudah ada.
                $owner = $code !== '' ? ($byCode[mb_strtolower($code)] ?? null) : null;
                if ($owner !== null && $owner->id !== $product->id) {
                    $fail("Kode \"{$code}\" sudah dipakai produk \"{$owner->name}\".");

                    continue;
                }
            }

            $plan['products'][] = ['product' => $product, 'category_key' => $categoryKey, 'fields' => $fields];
        }

        return $plan;
    }

    /** "Rp 18.000", "18,000", "18000", "18000.00" → 18000. Null bila bukan angka. */
    private function money(string $value): ?int
    {
        $v = preg_replace('/^rp\.?\s*/i', '', trim($value));
        $v = preg_replace('/[.,]\d{2}$/', '', $v); // desimal sen (mis. 18000.00)
        $digits = preg_replace('/[.,\s]/', '', $v);

        return preg_match('/^\d{1,12}$/', $digits) ? (int) $digits : null;
    }

    private function bool(string $value): ?bool
    {
        $v = mb_strtolower(trim($value));

        return match (true) {
            in_array($v, ['ya', 'y', 'yes', 'true', '1', 'aktif', 'active', 'favorit'], true) => true,
            in_array($v, ['tidak', 't', 'no', 'n', 'false', '0', 'nonaktif', 'non aktif', 'tidak aktif', 'inactive'], true) => false,
            default => null,
        };
    }
}
