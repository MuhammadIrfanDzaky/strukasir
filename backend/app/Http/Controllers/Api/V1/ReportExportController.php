<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Permission;
use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\ReportExportService;
use App\Support\Audit;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\URL;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Ekspor laporan CSV. Tablet meminta tautan bertanda tangan (berlaku 10 menit) lalu membukanya di
 * browser, sehingga file langsung tersimpan di folder Download tanpa izin penyimpanan di app.
 * Tautan terikat ke kedai, user, jenis & rentang tanggal; diubah sedikit saja = ditolak.
 */
class ReportExportController extends Controller
{
    private const LINK_MINUTES = 10;

    public function link(Request $request, TenantContext $context): JsonResponse
    {
        $data = $request->validate([
            'type' => ['required', Rule::in(array_keys(ReportExportService::TYPES))],
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d', 'after_or_equal:from'],
        ]);
        abort_if(now()->parse($data['from'])->diffInDays($data['to']) > 366, 422, 'Rentang maksimal 1 tahun.');

        // Relatif + host dari request: tautan tetap benar di emulator, tunnel, maupun domain produksi.
        $path = URL::temporarySignedRoute('reports.export', now()->addMinutes(self::LINK_MINUTES), [
            'tenant' => $context->id(),
            'user' => $request->user()->id,
            ...$data,
        ], absolute: false);

        return response()->json(['data' => [
            'url' => $request->getSchemeAndHttpHost().$path,
            'expires_in' => self::LINK_MINUTES * 60,
        ]]);
    }

    public function download(Request $request, TenantContext $context, ReportExportService $export): StreamedResponse
    {
        $data = $request->validate([
            'tenant' => ['required', 'uuid'],
            'user' => ['required', 'uuid'],
            'type' => ['required', Rule::in(array_keys(ReportExportService::TYPES))],
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d'],
        ]);

        // Izin dicek ulang saat diunduh: user yang dinonaktifkan / dicabut aksesnya tidak bisa memakai tautan lama.
        $user = $context->run($data['tenant'], fn () => User::query()->whereKey($data['user'])->where('active', true)->first());
        abort_unless($user !== null && Gate::forUser($user)->allows(Permission::ReportsView->value), 403);
        $context->run($data['tenant'], fn () => Audit::record('report.exported', null, after: [
            'type' => $data['type'], 'from' => $data['from'], 'to' => $data['to'],
        ], user: $user));

        $name = str_replace('_', '-', $data['type']).'_'.$data['from'].'_'.$data['to'].'.csv';

        return response()->streamDownload(function () use ($context, $export, $data) {
            $out = fopen('php://output', 'w');
            $context->run($data['tenant'], fn () => $export->write($data['type'], $data['from'], $data['to'], $out));
            fclose($out);
        }, $name, ['Content-Type' => 'text/csv; charset=UTF-8', 'Cache-Control' => 'no-store']);
    }
}
