<?php

namespace App\Http\Requests;

use App\Models\Customer;
use App\Models\TenantSetting;
use App\Support\PhoneNumber;
use Closure;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Daftar / ubah pelanggan. `code`, `anonymized_at` dan `tenant_id` tidak pernah diterima dari request.
 */
class CustomerRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        foreach (['phone', 'birth_date', 'note'] as $key) {
            if ($this->has($key) && is_string($this->input($key)) && trim($this->input($key)) === '') {
                $this->merge([$key => null]);
            }
        }
    }

    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:80', 'regex:/\S/'],
            'phone' => [$this->phoneRequired() ? 'required' : 'nullable', 'string', 'max:30', $this->validPhone(...)],
            'birth_date' => ['sometimes', 'nullable', 'date_format:Y-m-d', 'after_or_equal:1900-01-01', 'before_or_equal:today'],
            'note' => ['sometimes', 'nullable', 'string', 'max:200'],
        ];
    }

    public function messages(): array
    {
        return [
            'phone.required' => 'No HP wajib diisi.',
            'birth_date.before_or_equal' => 'Tanggal lahir tidak boleh di masa depan.',
        ];
    }

    /** Owner bisa mematikan "No HP wajib" di Pengaturan → Fitur. */
    private function phoneRequired(): bool
    {
        return (bool) TenantSetting::query()->value('customer_phone_required');
    }

    private function validPhone(string $attribute, mixed $value, Closure $fail): void
    {
        $phone = PhoneNumber::normalize((string) $value);
        if ($phone === null) {
            $fail('No HP tidak valid.');

            return;
        }
        // Pesan ramah lebih dulu; constraint unik di database tetap menjadi pengaman terakhir.
        $taken = Customer::query()->where('phone', $phone)
            ->when($this->route('customer'), fn ($q, Customer $self) => $q->whereKeyNot($self->id))
            ->first(['code', 'name', 'anonymized_at']);
        if ($taken !== null) {
            $fail("No HP ini sudah terdaftar atas nama {$taken->name} ({$taken->code}).");
        }
    }
}
