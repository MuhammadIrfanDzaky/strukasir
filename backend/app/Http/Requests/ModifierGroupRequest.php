<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class ModifierGroupRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:60'],
            'min_select' => ['required', 'integer', 'min:0', 'lte:max_select'],
            // Untuk grup berjumlah, max_select = batas TOTAL jumlah di grup (mis. maks. 3 tambahan).
            'max_select' => ['required', 'integer', 'min:1', 'max:20'],
            // Boleh pilih satu opsi lebih dari sekali (mis. Extra shot x2), maks. max_quantity per opsi.
            'allow_quantity' => ['sometimes', 'boolean'],
            'max_quantity' => ['sometimes', 'integer', 'min:1', 'max:20'],
            'sort' => ['sometimes', 'integer', 'min:0', 'max:10000'],
            // Muncul di kategori ini (produk baru langsung memakainya); kategori kedai lain tidak terlihat (RLS).
            'category_ids' => ['sometimes', 'nullable', 'array', 'max:100'],
            'category_ids.*' => ['uuid', 'distinct', Rule::exists('categories', 'id')],
            // Pasang juga ke produk yang SUDAH ada di kategori tersebut.
            'apply_to_existing' => ['sometimes', 'boolean'],
            'modifiers' => ['required', 'array', 'min:1', 'max:30'],
            'modifiers.*.id' => ['sometimes', 'nullable', 'uuid',
                Rule::exists('modifiers', 'id')->where('modifier_group_id', $this->route('modifierGroup')?->id)],
            'modifiers.*.name' => ['required', 'string', 'max:60'],
            'modifiers.*.price_delta' => ['required', 'integer', 'min:0', 'max:'.ProductRequest::MAX_PRICE],
            'modifiers.*.active' => ['sometimes', 'boolean'],
        ];
    }
}
