<?php

namespace App\Http\Requests;

use App\Models\Product;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class ProductRequest extends FormRequest
{
    public const MAX_PRICE = 100_000_000;

    /** Kode produk: huruf, angka, titik, minus, garis bawah (mis. BB03, KOPI-01). */
    public const CODE_PATTERN = '/^[A-Za-z0-9._-]{1,30}$/';

    protected function prepareForValidation(): void
    {
        if ($this->has('code')) {
            $code = trim((string) $this->input('code'));
            $this->merge(['code' => $code === '' ? null : $code]);
        }
    }

    public function rules(): array
    {
        return [
            'category_id' => ['required', 'uuid', Rule::exists('categories', 'id')],
            'code' => ['sometimes', 'nullable', 'string', 'regex:'.self::CODE_PATTERN, $this->uniqueCode(...)],
            'name' => ['required', 'string', 'max:80'],
            'price' => ['required', 'integer', 'min:0', 'max:'.self::MAX_PRICE],
            'cost' => ['sometimes', 'nullable', 'integer', 'min:0', 'max:'.self::MAX_PRICE],
            'active' => ['sometimes', 'boolean'],
            'sold_out' => ['sometimes', 'boolean'],
            'favorite' => ['sometimes', 'boolean'],
            'sort' => ['sometimes', 'integer', 'min:0', 'max:10000'],
            'modifier_group_ids' => ['sometimes', 'array', 'max:10'],
            'modifier_group_ids.*' => ['uuid', 'distinct', Rule::exists('modifier_groups', 'id')],
        ];
    }

    public function messages(): array
    {
        return ['code.regex' => 'Kode hanya boleh huruf, angka, titik, minus, atau garis bawah (maks. 30).'];
    }

    /** Unik per kedai (tanpa beda huruf besar/kecil). Query ter-scope tenant oleh global scope + RLS. */
    private function uniqueCode(string $attribute, mixed $value, Closure $fail): void
    {
        if ($value === null) {
            return;
        }
        $current = $this->route('product');
        $taken = Product::query()
            ->whereRaw('lower(code) = ?', [mb_strtolower((string) $value)])
            ->when($current instanceof Product, fn ($q) => $q->whereKeyNot($current->id))
            ->exists();
        if ($taken) {
            $fail('Kode produk sudah dipakai produk lain.');
        }
    }
}
