<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class PinLoginRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'user_id' => ['required', 'uuid'],
            'pin' => ['required', 'string', 'regex:/^\d{4,6}$/'],
        ];
    }
}
