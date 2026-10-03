<?php

namespace App\Console\Commands;

use App\Models\Tenant;
use App\Models\User;
use App\Services\TenantProvisioner;
use Database\Seeders\FeatureSeeder;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

/**
 * Daftarkan kedai baru di produksi. Password & PIN owner dibuat acak dan ditampilkan SEKALI;
 * serahkan langsung ke owner dan minta ia menggantinya.
 */
class CreateTenant extends Command
{
    protected $signature = 'pos:create-tenant
        {code : Kode unik kedai, mis. berrybrew}
        {name : Nama kedai di struk, mis. "BerryBrew"}
        {--owner-name=Owner : Nama owner}
        {--owner-email= : Email login owner}
        {--plan=standard : Kode paket}';

    protected $description = 'Buat kedai baru beserta akun owner';

    public function handle(TenantProvisioner $provisioner): int
    {
        $data = [
            'code' => $this->argument('code'),
            'name' => $this->argument('name'),
            'email' => $this->option('owner-email'),
        ];

        $validator = Validator::make($data, [
            'code' => ['required', 'alpha_dash', 'max:40'],
            'name' => ['required', 'string', 'max:80'],
            'email' => ['required', 'email'],
        ]);
        if ($validator->fails()) {
            foreach ($validator->errors()->all() as $error) {
                $this->error($error);
            }

            return self::FAILURE;
        }
        if (Tenant::where('code', $data['code'])->exists()) {
            $this->error("Kode kedai '{$data['code']}' sudah dipakai.");

            return self::FAILURE;
        }
        if (User::where('email', strtolower($data['email']))->exists()) {
            $this->error('Email sudah dipakai owner kedai lain.');

            return self::FAILURE;
        }

        // Fitur & paket dasar harus ada (idempotent).
        $this->callSilently('db:seed', ['--class' => FeatureSeeder::class, '--force' => true]);

        $password = Str::password(16, symbols: false);
        $pin = (string) random_int(100000, 999999);
        $tenant = $provisioner->create($data['code'], $data['name'], $this->option('owner-name'), $data['email'], $password, $pin, $this->option('plan'));

        $this->info("Kedai '{$tenant->name}' dibuat.");
        $this->warn('Kredensial owner (ditampilkan sekali, serahkan langsung ke owner):');
        $this->line("  Email   : {$data['email']}");
        $this->line("  Password: {$password}");
        $this->line("  PIN     : {$pin}");

        return self::SUCCESS;
    }
}
