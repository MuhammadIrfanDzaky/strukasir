<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class TenantSetting extends Model
{
    use BelongsToTenant;

    protected $primaryKey = 'tenant_id';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'receipt_name', 'receipt_header', 'receipt_footer',
        'tax_enabled', 'tax_rate_bp', 'service_enabled', 'service_rate_bp',
        'rounding_unit', 'cashier_discount_limit_bp', 'tax_inclusive', 'service_inclusive', 'customer_phone_required', 'credit_default_limit', 'report_email', 'report_whatsapp',
        'order_types_enabled', 'default_order_type', 'qris_image', 'qris_on_bill',
    ];

    protected function casts(): array
    {
        return [
            'tax_enabled' => 'boolean',
            'service_enabled' => 'boolean',
            'tax_inclusive' => 'boolean',
            'service_inclusive' => 'boolean',
            'customer_phone_required' => 'boolean',
            'report_email' => 'boolean',
            'order_types_enabled' => 'boolean',
            'qris_on_bill' => 'boolean',
            'tax_rate_bp' => 'integer',
            'service_rate_bp' => 'integer',
            'rounding_unit' => 'integer',
            'cashier_discount_limit_bp' => 'integer',
        ];
    }
}
