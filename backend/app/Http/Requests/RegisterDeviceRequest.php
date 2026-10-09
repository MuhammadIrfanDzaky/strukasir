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
            // Kode 6 digit authenticator; wajib hanya bila owner mengaktifkan 2FA (dicek di controller).
            'otp' => ['nullable', 'string', 'max:10'],
            // Opsional: kosong → "Tablet N".
            'device_name' => ['nullable', 'string', 'max:60'],
            // UUID yang dibuat tablet sekali per instalasi → daftar ulang setelah timeout tidak membuat tablet ganda.
            'device_id' => ['nullable', 'uuid'],
            // Usaha dengan beberapa outlet: outlet tablet ini (server meminta bila belum diisi).
            'outlet_id' => ['nullable', 'uuid'],
        ];
    }
}
