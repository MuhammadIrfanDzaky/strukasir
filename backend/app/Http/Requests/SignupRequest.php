<?php

namespace App\Http\Requests;

use App\Enums\BusinessSector;
use App\Enums\SalesMode;
use App\Services\ReferralService;
use App\Support\PlanCatalog;
use App\Support\Regions;
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
            // Kode dari POST /signup/email-code (dicek di controller, sekali pakai).
            'email_code' => ['required', 'string', 'max:10'],
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
            // "Lainnya" → wajib sebutkan (bahan template baru).
            'sector_other' => ['nullable', 'required_if:sector,other', 'string', 'max:60'],
            // Hanya usaha makanan & minuman yang ditanya cara berjualan; selain itu diabaikan.
            'sales_mode' => [Rule::requiredIf(fn () => $this->sector()?->asksSalesMode() ?? false), 'nullable', Rule::enum(SalesMode::class)],
            'province_code' => ['required', 'string', function (string $attribute, mixed $value, Closure $fail) {
                if (! is_string($value) || ! Regions::provinceExists($value)) {
                    $fail('Pilih provinsi dari daftar.');
                }
            }],
            'regency_code' => ['required', 'string', function (string $attribute, mixed $value, Closure $fail) {
                if (! is_string($value) || ! Regions::regencyIn((string) $this->input('province_code'), $value)) {
                    $fail('Pilih kota/kabupaten di provinsi tersebut.');
                }
            }],
            'phone' => ['nullable', 'string', 'regex:/^\+?[0-9 \-]{8,20}$/'],
            'address' => ['nullable', 'string', 'max:300'],
            'terms' => ['accepted'],

            // Paket: Gratis (coba 7 hari) atau paket berbayar (menunggu pembayaran). Kosong = Gratis.
            'plan' => ['nullable', 'string', Rule::exists('plans', 'code')->where('public', true)],
            'period' => ['nullable', Rule::in(array_keys(PlanCatalog::PERIODS))],
            // Kode referral usaha pengajak (opsional): coba 14 hari + diskon 25% pembayaran pertama.
            'referral_code' => ['nullable', 'string', 'max:12', function (string $attribute, mixed $value, Closure $fail) {
                if (app(ReferralService::class)->findReferrer(is_string($value) ? $value : null) === null) {
                    $fail('Kode referral tidak ditemukan.');
                }
            }],

            // Tablet pertama (sama seperti /devices/register)
            'device_id' => ['nullable', 'uuid'],
            'device_name' => ['nullable', 'string', 'max:60'],
        ];
    }

    public function sector(): ?BusinessSector
    {
        return BusinessSector::tryFrom((string) $this->input('sector'));
    }

    public function messages(): array
    {
        return [
            'sector_other.required_if' => 'Sebutkan bidang usaha Anda.',
            'sales_mode.required' => 'Pilih cara berjualan.',
            'email.unique' => 'Email ini sudah terdaftar. Pilih "Masuk" untuk mendaftarkan tablet ke usaha yang sudah ada.',
            'terms.accepted' => 'Setujui syarat & ketentuan untuk melanjutkan.',
            'phone.regex' => 'Nomor HP tidak valid.',
            'plan.exists' => 'Pilih paket dari daftar.',
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
