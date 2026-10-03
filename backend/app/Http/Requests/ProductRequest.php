<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class ProductRequest extends FormRequest
{
    public const MAX_PRICE = 100_000_000;

    public function rules(): array
    {
        return [
            'category_id' => ['required', 'uuid', Rule::exists('categories', 'id')],
            'name' => ['required', 'string', 'max:80'],
            'price' => ['required', 'integer', 'min:0', 'max:'.self::MAX_PRICE],
            'active' => ['sometimes', 'boolean'],
            'sold_out' => ['sometimes', 'boolean'],
            'sort' => ['sometimes', 'integer', 'min:0', 'max:10000'],
            'modifier_group_ids' => ['sometimes', 'array', 'max:10'],
            'modifier_group_ids.*' => ['uuid', 'distinct', Rule::exists('modifier_groups', 'id')],
        ];
    }
}
