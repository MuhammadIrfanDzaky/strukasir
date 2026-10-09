<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Feature;
use App\Http\Controllers\Controller;
use App\Models\MemberTier;
use App\Models\TenantSetting;
use App\Services\TierService;
use App\Support\Audit;
use App\Support\Tenancy\FeatureGate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Pengaturan → Tingkat member (owner): dasar kenaikan (belanja / kunjungan), jendela waktu, dan
 * daftar tingkat dengan manfaatnya. Tingkat yang dibuang dinonaktifkan (salinan di order tetap).
 */
class TierController extends Controller
{
    public function show(FeatureGate $features, TierService $tiers): JsonResponse
    {
        abort_unless($features->enabled(Feature::MemberTiers), 403, 'Fitur tingkat member tidak aktif untuk kedai ini.');

        return response()->json(['data' => $this->present($tiers)]);
    }

    public function update(Request $request, FeatureGate $features, TierService $tiers): JsonResponse
    {
        abort_unless($features->enabled(Feature::MemberTiers), 403, 'Fitur tingkat member tidak aktif untuk kedai ini.');

        $data = $request->validate([
            'basis' => ['required', Rule::in(['spend', 'visits'])],
            'window_months' => ['nullable', 'integer', 'min:1', 'max:36'],
            'tiers' => ['present', 'array', 'max:6'],
            'tiers.*.id' => ['nullable', 'uuid', 'distinct'],
            'tiers.*.name' => ['required', 'string', 'max:30', 'regex:/\S/', 'distinct:ignore_case'],
            'tiers.*.threshold' => ['required', 'integer', 'min:0', 'max:10000000000', 'distinct'],
            'tiers.*.discount_bp' => ['required', 'integer', 'min:0', 'max:5000'],
            'tiers.*.earn_multiplier' => ['required', 'integer', 'min:1', 'max:5'],
            'tiers.*.color' => ['required', Rule::in(TierService::COLORS)],
        ], [
            'tiers.*.threshold.distinct' => 'Ambang tiap tingkat harus berbeda.',
            'tiers.*.name.distinct' => 'Nama tingkat tidak boleh sama.',
            'tiers.*.discount_bp.max' => 'Diskon tingkat maksimal 50%.',
        ]);

        $before = $this->present($tiers);
        DB::transaction(function () use ($data) {
            TenantSetting::query()->firstOrFail()->forceFill([
                'tier_basis' => $data['basis'],
                'tier_window_months' => $data['window_months'] ?? null,
            ])->save();

            $keep = [];
            foreach ($data['tiers'] as $t) {
                $tier = isset($t['id']) ? MemberTier::query()->find($t['id']) : null;
                $tier ??= new MemberTier;
                $tier->fill([
                    'name' => trim($t['name']),
                    'threshold' => $t['threshold'],
                    'discount_bp' => $t['discount_bp'],
                    'earn_multiplier' => $t['earn_multiplier'],
                    'color' => $t['color'],
                    'active' => true,
                ])->save();
                $keep[] = $tier->id;
            }
            MemberTier::query()->whereNotIn('id', $keep)->where('active', true)->update(['active' => false, 'updated_at' => now()]);
        });

        request()->attributes->remove('member_tiers');
        $after = $this->present($tiers);
        Audit::record('tiers.updated', null, before: $before, after: $after);

        return response()->json(['data' => $after]);
    }

    /** @return array<string, mixed> */
    private function present(TierService $tiers): array
    {
        return [
            ...$tiers->settings(),
            'tiers' => $tiers->tiers()->map(fn (MemberTier $t) => TierService::present($t))->values(),
        ];
    }

    /** @throws ValidationException */
    public static function assertTier(?string $tierId): ?MemberTier
    {
        if ($tierId === null) {
            return null;
        }

        return MemberTier::query()->where('active', true)->find($tierId)
            ?? throw ValidationException::withMessages(['tier_id' => 'Tingkat tidak ditemukan.']);
    }
}
