<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

/**
 * PUT /orders/{uuid}: buat atau ganti isi order yang masih terbuka. Harga TIDAK dikirim klien;
 * server menghitung dari menu. `expected_total` hanya untuk mendeteksi menu tablet yang basi.
 */
class UpsertOrderRequest extends FormRequest
{
    public function rules(): array
    {
        return [
            'customer_label' => ['nullable', 'string', 'max:60'],
            'client_created_at' => ['nullable', 'date'],
            'expected_total' => ['required', 'integer', 'min:0'],
            'items' => ['required', 'array', 'min:1', 'max:100'],
            'items.*.id' => ['required', 'uuid', 'distinct'],
            'items.*.product_id' => ['required', 'uuid'],
            'items.*.qty' => ['required', 'integer', 'min:1', 'max:999'],
            'items.*.note' => ['nullable', 'string', 'max:120'],
            // ID yang sama diulang = jumlah (Extra shot x2 → dua kali ID-nya). Hanya boleh untuk grup
            // berjumlah; aturan per grup dicek di OrderService.
            'items.*.modifier_ids' => ['present', 'array', 'max:60'],
            'items.*.modifier_ids.*' => ['uuid'],
            'items.*.discount' => ['nullable', 'array:type,value'],
            'items.*.discount.type' => ['required_with:items.*.discount', 'in:amount,percent'],
            'items.*.discount.value' => ['required_with:items.*.discount', 'integer', 'min:0'],
            'order_discount' => ['nullable', 'array:type,value'],
            'order_discount.type' => ['required_with:order_discount', 'in:amount,percent'],
            'order_discount.value' => ['required_with:order_discount', 'integer', 'min:0'],
            'approval' => ['nullable', 'array:user_id,pin'],
            'approval.user_id' => ['required_with:approval', 'uuid'],
            'approval.pin' => ['required_with:approval', 'string', 'regex:/^\d{4,6}$/'],
        ];
    }
}
