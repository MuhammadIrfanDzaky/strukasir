<?php

namespace App\Http\Requests;

use App\Support\ReceiptLogo;
use Closure;
use Illuminate\Foundation\Http\FormRequest;

/**
 * PUT /settings/receipt: nama, alamat (header), pesan penutup (footer), dan logo struk.
 * `logo` = PNG base64 (sudah diperkecil & hitam-putih di tablet); `remove_logo` = hapus logo.
 */
class ReceiptSettingsRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:40'],
            'header' => ['nullable', 'string', 'max:300'],
            'footer' => ['nullable', 'string', 'max:300'],
            'logo' => ['nullable', 'string', 'max:'.ReceiptLogo::MAX_BASE64, function (string $attribute, mixed $value, Closure $fail) {
                if (is_string($value) && ($error = ReceiptLogo::validate($value)) !== null) {
                    $fail($error);
                }
            }],
            'remove_logo' => ['sometimes', 'boolean'],
        ];
    }
}
