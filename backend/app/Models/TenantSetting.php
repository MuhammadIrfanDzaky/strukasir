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
        'rounding_unit', 'cashier_discount_limit_bp',
    ];

    protected function casts(): array
    {
        return [
            'tax_enabled' => 'boolean',
            'service_enabled' => 'boolean',
            'tax_rate_bp' => 'integer',
            'service_rate_bp' => 'integer',
            'rounding_unit' => 'integer',
            'cashier_discount_limit_bp' => 'integer',
        ];
    }
}
