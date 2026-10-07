<?php

namespace App\Http\Requests;

use App\Enums\BusinessSector;
use App\Enums\SalesMode;
use Closure;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

/** POST /signup: pendaftaran usaha baru oleh calon owner dari app (publik, di-throttle). */
class SignupRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        if (is_string($this->input('email'))) {
            $this->merge(['email' => strtolower(trim($this->input('email')))]);
        }
    }

    public function rules(): array
    {
        return [
            // Akun owner
            'owner_name' => ['required', 'string', 'max:60'],
            'email' => ['required', 'email:rfc', 'max:255', 'unique:users,email'],
            // SEC-10: minimal 8 karakter, ada huruf & angka. Tidak memakai uncompromised() (butuh internet keluar).
            'password' => ['required', 'string', 'max:255', Password::min(8)->letters()->numbers()],
            'pin' => ['required', 'digits:6', function (string $attribute, mixed $value, Closure $fail) {
                if (self::weakPin((string) $value)) {
                    $fail('PIN terlalu mudah ditebak. Hindari angka sama semua atau berurutan.');
                }
            }],

            // Usaha
            'business_name' => ['required', 'string', 'max:80'],
            'sector' => ['required', Rule::enum(BusinessSector::class)],
            'sales_mode' => ['required', Rule::enum(SalesMode::class)],
            'outlet_count' => ['required', 'integer', 'between:1,999'],
            'phone' => ['nullable', 'string', 'regex:/^\+?[0-9 \-]{8,20}$/'],
            'address' => ['nullable', 'string', 'max:300'],
            'terms' => ['accepted'],

            // Tablet pertama (sama seperti /devices/register)
            'device_id' => ['nullable', 'uuid'],
            'device_name' => ['nullable', 'string', 'max:60'],
        ];
    }

    public function messages(): array
    {
        return [
            'email.unique' => 'Email ini sudah terdaftar. Pilih "Masuk" untuk mendaftarkan tablet ke usaha yang sudah ada.',
            'terms.accepted' => 'Setujui syarat & ketentuan untuk melanjutkan.',
            'phone.regex' => 'Nomor HP tidak valid.',
        ];
    }

    /** 000000, 111111, 123456, 654321, dst. */
    public static function weakPin(string $pin): bool
    {
        if (count(array_unique(str_split($pin))) === 1) {
            return true;
        }

        return str_contains('01234567890', $pin) || str_contains('09876543210', $pin);
    }
}
