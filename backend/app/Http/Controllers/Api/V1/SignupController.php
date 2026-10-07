<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Requests\SignupRequest;
use App\Models\Plan;
use App\Models\User;
use App\Services\DeviceRegistrar;
use App\Services\EmailCodes;
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
        EmailCodes $emailCodes,
    ): JsonResponse {
        if (! Plan::where('code', 'standard')->exists()) {
            report(new \RuntimeException('Paket "standard" belum ada: jalankan FeatureSeeder.'));

            return response()->json(['message' => 'Pendaftaran sedang tidak tersedia. Coba lagi nanti.'], 503);
        }

        $data = $request->validated();

        return DB::transaction(function () use ($data, $provisioner, $registrar, $context, $emailCodes) {
            $tenant = $provisioner->create(
                code: $provisioner->uniqueCode($data['business_name']),
                name: trim($data['business_name']),
                ownerName: trim($data['owner_name']),
                ownerEmail: $data['email'],
                ownerPassword: $data['password'],
                ownerPin: $data['pin'],
                profile: [
                    'sector' => $data['sector'],
                    'sales_mode' => $data['sales_mode'],
                    'outlet_count' => (int) $data['outlet_count'],
                    'phone' => isset($data['phone']) ? preg_replace('/[ \-]/', '', $data['phone']) : null,
                    'terms_accepted_at' => now(),
                ],
                receiptHeader: isset($data['address']) ? trim($data['address']) ?: null : null,
            );

            return $context->run($tenant->id, function () use ($tenant, $data, $registrar, $emailCodes) {
                $owner = User::query()->where('role', Role::Owner)->firstOrFail();
                [$device, $token] = $registrar->register($tenant, $data['device_id'] ?? null, $data['device_name'] ?? null);

                // Titik awal sesuai jenis usaha & cara jualan (fitur + kategori kosong); bisa diubah owner.
                $template = BusinessTemplate::for($tenant->sector, $tenant->sales_mode);
                $template->apply($tenant->id, $tenant->plan_id);

                Audit::record('tenant.signup', $tenant, after: [
                    'sector' => $data['sector'], 'sales_mode' => $data['sales_mode'], 'outlet_count' => (int) $data['outlet_count'],
                    'template' => ['features' => $template->features, 'categories' => $template->categories],
                ], user: $owner, device: $device);
                // Kode verifikasi email langsung dikirim; gagal kirim tidak membatalkan pendaftaran
                // (owner bisa minta ulang dari app).
                $emailCodes->send($owner, EmailCodes::VERIFY_EMAIL);

                Audit::record('device.registered', $device, after: ['code' => $device->code, 'name' => $device->name],
                    user: $owner, device: $device);

                // owner_id: app langsung login PIN owner (PIN baru saja dibuat di layar yang sama).
                return response()->json(DeviceRegistrar::response($tenant, $device, $token) + ['owner_id' => $owner->id], 201);
            });
        });
    }
}
