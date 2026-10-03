<?php

namespace App\Http\Resources;

use App\Models\Order;
use App\Models\OrderItem;
use App\Models\OrderItemModifier;
use App\Models\Payment;
use App\Models\TenantSetting;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Order lengkap — cukup untuk mencetak struk / checker tanpa memanggil endpoint lain.
 *
 * @mixin Order
 */
class OrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $this->resource->loadMissing(['items.modifiers', 'payments', 'cashier:id,name']);
        $settings = TenantSetting::query()->first();

        return [
            'id' => $this->id,
            'number' => $this->number,
            'status' => $this->status,
            'business_date' => $this->business_date->toDateString(),
            'customer_label' => $this->customer_label,
            'cashier' => $this->cashier?->name,
            'currency' => $this->currency,
            'items' => $this->items->map(fn (OrderItem $i) => [
                'id' => $i->id,
                'product_id' => $i->product_id,
                'name' => $i->name,
                'unit_price' => $i->unit_price,
                'modifiers_total' => $i->modifiers_total,
                'qty' => $i->qty,
                'note' => $i->note,
                'discount' => $i->discount_type ? ['type' => $i->discount_type, 'value' => $i->discount_value] : null,
                'discount_total' => $i->discount_total,
                'line_total' => $i->line_total,
                'modifiers' => $i->modifiers->map(fn (OrderItemModifier $m) => [
                    'modifier_id' => $m->modifier_id,
                    'group_name' => $m->group_name,
                    'name' => $m->name,
                    'price_delta' => $m->price_delta,
                ]),
            ]),
            'order_discount' => $this->order_discount_type
                ? ['type' => $this->order_discount_type, 'value' => $this->order_discount_value] : null,
            'subtotal' => $this->subtotal,
            'discount_total' => $this->discount_total,
            'service_total' => $this->service_total,
            'tax_total' => $this->tax_total,
            'rounding' => $this->rounding,
            'grand_total' => $this->grand_total,
            'paid_total' => $this->paid_total,
            'change_total' => $this->change_total,
            'payments' => $this->payments->where('kind', 'payment')->values()->map(fn (Payment $p) => [
                'id' => $p->id,
                'method' => $p->method,
                'amount' => $p->amount,
                'tendered' => $p->tendered,
                'change' => $p->change,
                'confirmed_at' => $p->confirmed_at->toIso8601String(),
            ]),
            'created_at' => $this->created_at->toIso8601String(),
            'paid_at' => $this->paid_at?->toIso8601String(),
            'receipt' => [
                'name' => $settings?->receipt_name,
                'header' => $settings?->receipt_header,
                'footer' => $settings?->receipt_footer,
            ],
        ];
    }
}
