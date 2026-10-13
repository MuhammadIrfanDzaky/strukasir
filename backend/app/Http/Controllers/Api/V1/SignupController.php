<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Requests\SignupRequest;
use App\Models\Plan;
use App\Models\User;
use App\Services\DeviceRegistrar;
use App\Services\SignupCodes;
use App\Services\TenantProvisioner;
use App\Support\Audit;
use App\Support\BusinessTemplate;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * Pendaftaran mandiri: calon owner membuat usaha + akun owner dari app, dan tablet yang dipakai
 * mendaftar langsung terdaftar sebagai tablet pertama. Respons sama dengan /devices/register,
 * jadi app langsung lanjut ke login PIN.
 */
class SignupController extends Controller
{
    public function __invoke(
        SignupRequest $request,
        TenantProvisioner $provisioner,
        DeviceRegistrar $registrar,
        TenantContext $context,
        SignupCodes $signupCodes,
    ): JsonResponse {
        if (! Plan::where('code', 'standard')->exists()) {
            report(new \RuntimeException('Paket "standard" belum ada: jalankan FeatureSeeder.'));

            return response()->json(['message' => 'Pendaftaran sedang tidak tersedia. Coba lagi nanti.'], 503);
        }

        $data = $request->validated();

        return DB::transaction(function () use ($data, $request, $provisioner, $registrar, $context, $signupCodes) {
            // Email harus terbukti milik pendaftar sebelum usaha dibuat.
            if (! $signupCodes->consume($data['email'], trim($data['email_code']))) {
                return response()->json([
                    'message' => 'Kode verifikasi salah atau sudah kedaluwarsa.',
                    'errors' => ['email_code' => ['Kode salah atau sudah kedaluwarsa. Minta kode baru bila perlu.']],
                ], 422);
            }

            $tenant = $provisioner->create(
                code: $provisioner->uniqueCode($data['business_name']),
                name: trim($data['business_name']),
                ownerName: trim($data['owner_name']),
                ownerEmail: $data['email'],
                ownerPassword: $data['password'],
                ownerPin: $data['pin'],
                profile: [
                    'sector' => $data['sector'],
                    'sector_other' => $data['sector'] === 'other' ? trim($data['sector_other']) : null,
                    // Usaha non makanan tidak ditanya cara jualan.
                    'sales_mode' => $request->sector()->asksSalesMode() ? $data['sales_mode'] : null,
                    'province_code' => $data['province_code'],
                    'regency_code' => $data['regency_code'],
                    'phone' => isset($data['phone']) ? preg_replace('/[ \-]/', '', $data['phone']) : null,
                    'terms_accepted_at' => now(),
                ],
                receiptHeader: isset($data['address']) ? trim($data['address']) ?: null : null,
            );

            return $context->run($tenant->id, function () use ($tenant, $data, $registrar) {
                $owner = User::query()->where('role', Role::Owner)->firstOrFail();
                $owner->forceFill(['email_verified_at' => now()])->save();
                [$device, $token] = $registrar->register($tenant, $data['device_id'] ?? null, $data['device_name'] ?? null);

                // Titik awal sesuai jenis usaha & cara jualan (fitur + kategori kosong); bisa diubah owner.
                $template = BusinessTemplate::for($tenant->sector, $tenant->sales_mode);
                $template->apply($tenant->id, $tenant->plan_id);

                Audit::record('tenant.signup', $tenant, after: [
                    'sector' => $data['sector'], 'sales_mode' => $tenant->sales_mode?->value,
                    'template' => ['features' => $template->features, 'categories' => $template->categories],
                ], user: $owner, device: $device);
                Audit::record('device.registered', $device, after: ['code' => $device->code, 'name' => $device->name],
                    user: $owner, device: $device);

                // owner_id: app langsung login PIN owner (PIN baru saja dibuat di layar yang sama).
                return response()->json(DeviceRegistrar::response($tenant, $device, $token) + ['owner_id' => $owner->id], 201);
            });
        });
    }
}
