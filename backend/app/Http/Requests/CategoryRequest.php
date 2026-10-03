<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class CategoryRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            // RLS membuat aturan unique/exists otomatis hanya melihat data kedai ini.
            'name' => ['required', 'string', 'max:60',
                Rule::unique('categories', 'name')->ignore($this->route('category'))],
            'sort' => ['sometimes', 'integer', 'min:0', 'max:10000'],
            'active' => ['sometimes', 'boolean'],
        ];
    }
}
