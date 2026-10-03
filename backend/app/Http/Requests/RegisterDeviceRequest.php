<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class RegisterDeviceRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'email' => ['required', 'email', 'max:255'],
            'password' => ['required', 'string', 'max:255'],
            'device_name' => ['required', 'string', 'max:60'],
            // UUID yang dibuat tablet sekali per instalasi → daftar ulang setelah timeout tidak membuat tablet ganda.
            'device_id' => ['nullable', 'uuid'],
        ];
    }
}
