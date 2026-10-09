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
            // credit = kasbon member (fitur customer_credit); dicek di CreditService.
            'payments.*.method' => ['required', 'in:cash,debit,qris,credit'],
            'payments.*.amount' => ['required', 'integer', 'min:1'],
            'payments.*.tendered' => ['nullable', 'integer', 'min:1'],
            'payments.*.reference' => ['nullable', 'string', 'max:60'],
            // PIN owner bila kasbon melewati batas.
            'approval' => ['nullable', 'array:user_id,pin'],
            'approval.user_id' => ['required_with:approval', 'uuid'],
            'approval.pin' => ['required_with:approval', 'string', 'regex:/^\d{4,6}$/'],
        ];
    }
}
