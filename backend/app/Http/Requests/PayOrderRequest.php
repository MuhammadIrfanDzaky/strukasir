<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/** POST /orders/{uuid}/pay. ID pembayaran dibuat tablet → kirim ulang aman (idempotent). */
class PayOrderRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'expected_total' => ['required', 'integer', 'min:0'],
            'payments' => ['present', 'array', 'max:5'],
            'payments.*.id' => ['required', 'uuid', 'distinct'],
            'payments.*.method' => ['required', 'in:cash,debit,qris'],
            'payments.*.amount' => ['required', 'integer', 'min:1'],
            'payments.*.tendered' => ['nullable', 'integer', 'min:1'],
            'payments.*.reference' => ['nullable', 'string', 'max:60'],
        ];
    }
}
