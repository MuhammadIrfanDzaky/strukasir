<?php

namespace App\Http\Controllers\Api\V1;

use App\Enums\Feature;
use App\Http\Controllers\Controller;
use App\Models\LoyaltyProgram;
use App\Models\LoyaltyReward;
use App\Services\LoyaltyService;
use App\Support\Audit;
use App\Support\Tenancy\FeatureGate;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Pengaturan → Program loyalitas (owner): cara dapat stempel/poin, masa berlaku, dan daftar hadiah.
 * Hadiah yang dihapus dari daftar dinonaktifkan (riwayat tukar tetap merujuknya).
 * Perubahan ikut versi menu, jadi semua tablet memuat program terbaru.
 */
class LoyaltyController extends Controller
{
    public function show(FeatureGate $features): JsonResponse
    {
        abort_unless($features->enabled(Feature::Loyalty), 403, 'Fitur program loyalitas tidak aktif untuk kedai ini.');

        return response()->json(['data' => $this->present()]);
    }

    public function update(Request $request, FeatureGate $features): JsonResponse
    {
        abort_unless($features->enabled(Feature::Loyalty), 403, 'Fitur program loyalitas tidak aktif untuk kedai ini.');

        $data = $request->validate([
            'active' => ['required', 'boolean'],
            'name' => ['required', 'string', 'max:40', 'regex:/\S/'],
            'earn_mode' => ['required', Rule::in(['per_item', 'per_order', 'per_amount'])],
            'earn_per_amount' => ['nullable', 'required_if:earn_mode,per_amount', 'integer', 'min:100', 'max:10000000'],
            'earn_min_order' => ['nullable', 'integer', 'min:0', 'max:100000000'],
            'category_ids' => ['nullable', 'array', 'max:50'],
            'category_ids.*' => ['uuid', 'distinct', Rule::exists('categories', 'id')],
            'expiry_months' => ['nullable', 'integer', 'min:1', 'max:60'],
            'rewards' => ['present', 'array', 'max:20'],
            'rewards.*.id' => ['nullable', 'uuid', 'distinct'],
            'rewards.*.name' => ['required', 'string', 'max:60', 'regex:/\S/'],
            'rewards.*.cost' => ['required', 'integer', 'min:1', 'max:100000'],
            'rewards.*.type' => ['required', Rule::in(['free_product', 'amount', 'percent'])],
            'rewards.*.product_id' => ['nullable', 'required_if:rewards.*.type,free_product', 'uuid', Rule::exists('products', 'id')],
            'rewards.*.value' => ['nullable', 'integer', 'min:0', 'max:100000000'],
        ], [
            'earn_per_amount.required_if' => 'Isi kelipatan belanja untuk 1 poin.',
            'rewards.*.product_id.required_if' => 'Pilih produk yang digratiskan.',
        ]);

        // Nilai potongan sesuai jenis: Rp untuk "amount", basis poin (1–100%) untuk "percent".
        $errors = [];
        foreach ($data['rewards'] as $i => $r) {
            $value = (int) ($r['value'] ?? 0);
            if ($r['type'] === 'amount' && $value < 1) {
                $errors["rewards.{$i}.value"] = 'Isi besar potongan (Rp).';
            }
            if ($r['type'] === 'percent' && ($value < 1 || $value > 10000)) {
                $errors["rewards.{$i}.value"] = 'Potongan persen harus 1–100%.';
            }
        }
        if ($data['active'] && $data['rewards'] === []) {
            $errors['rewards'] = 'Tambahkan minimal satu hadiah sebelum program dinyalakan.';
        }
        if ($errors !== []) {
            throw ValidationException::withMessages($errors);
        }

        $before = $this->present();
        DB::transaction(function () use ($data) {
            $program = LoyaltyProgram::query()->first() ?? new LoyaltyProgram;
            $program->fill([
                'active' => $data['active'],
                'name' => trim($data['name']),
                'earn_mode' => $data['earn_mode'],
                'earn_per_amount' => $data['earn_mode'] === 'per_amount' ? $data['earn_per_amount'] : null,
                'earn_min_order' => $data['earn_mode'] === 'per_order' ? ($data['earn_min_order'] ?? 0) : null,
                'category_ids' => $data['earn_mode'] === 'per_item' ? array_values($data['category_ids'] ?? []) : null,
                'expiry_months' => $data['expiry_months'] ?? null,
            ])->save();

            $keep = [];
            foreach ($data['rewards'] as $i => $r) {
                $reward = isset($r['id']) ? LoyaltyReward::query()->find($r['id']) : null;
                $reward ??= new LoyaltyReward;
                $reward->fill([
                    'name' => trim($r['name']),
                    'cost' => $r['cost'],
                    'type' => $r['type'],
                    'product_id' => $r['type'] === 'free_product' ? $r['product_id'] : null,
                    'value' => $r['type'] === 'free_product' ? 0 : (int) $r['value'],
                    'active' => true,
                    'sort' => $i,
                ])->save();
                $keep[] = $reward->id;
            }
            LoyaltyReward::query()->whereNotIn('id', $keep)->where('active', true)->update(['active' => false, 'updated_at' => now()]);
        });

        $after = $this->present();
        Audit::record('loyalty.updated', null, before: $before, after: $after);

        return response()->json(['data' => $after]);
    }

    /** @return array<string, mixed> */
    private function present(): array
    {
        $program = LoyaltyProgram::query()->first();

        return [
            'program' => $program ? LoyaltyService::presentProgram($program) : null,
            'rewards' => LoyaltyReward::query()->where('active', true)->orderBy('sort')->orderBy('cost')->get()
                ->map(fn (LoyaltyReward $r) => LoyaltyService::presentReward($r))->values(),
        ];
    }
}
