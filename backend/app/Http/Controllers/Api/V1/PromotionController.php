<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Promotion;
use App\Models\Voucher;
use App\Services\PromotionService;
use App\Support\Audit;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Promo & voucher (fitur `promotions`). Owner: atur promo & voucher. Kasir: cek kode voucher
 * (syaratnya dipakai tablet menghitung total; server tetap menghitung ulang saat simpan & bayar).
 */
class PromotionController extends Controller
{
    public function __construct(private readonly PromotionService $promotions) {}

    public function index(): JsonResponse
    {
        $this->guard();

        return response()->json(['data' => [
            'promotions' => Promotion::query()->orderByDesc('active')->orderBy('name')->get()
                ->map(fn (Promotion $p) => PromotionService::presentPromotion($p))->values(),
            'vouchers' => Voucher::query()->orderByDesc('active')->orderBy('code')->get()
                ->map(fn (Voucher $v) => PromotionService::presentVoucher($v, $this->promotions->usage($v)))->values(),
        ]]);
    }

    public function savePromotion(Request $request, ?Promotion $promotion = null): JsonResponse
    {
        $this->guard();
        $data = $request->validate([
            'name' => ['required', 'string', 'max:40', 'regex:/\S/'],
            'type' => ['required', Rule::in(['percent', 'amount', 'bogo'])],
            'value' => ['nullable', 'integer', 'min:0', 'max:100000000'],
            'buy_qty' => ['nullable', 'integer', 'min:1', 'max:50'],
            'free_qty' => ['nullable', 'integer', 'min:1', 'max:50'],
            'scope' => ['required', Rule::in(['all', 'categories', 'products'])],
            'target_ids' => ['nullable', 'array', 'max:100'],
            'target_ids.*' => ['uuid', 'distinct'],
            'days' => ['nullable', 'array', 'max:7'],
            'days.*' => ['integer', 'between:1,7', 'distinct'],
            'start_time' => ['nullable', 'date_format:H:i', 'required_with:end_time'],
            'end_time' => ['nullable', 'date_format:H:i', 'required_with:start_time', 'different:start_time'],
            'starts_on' => ['nullable', 'date_format:Y-m-d'],
            'ends_on' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:starts_on'],
            'active' => ['sometimes', 'boolean'],
        ]);
        $errors = match ($data['type']) {
            'percent' => ($data['value'] ?? 0) < 1 || $data['value'] > 10000 ? ['value' => 'Potongan persen harus 1–100%.'] : [],
            'amount' => ($data['value'] ?? 0) < 1 ? ['value' => 'Isi potongan per item (Rp).'] : [],
            default => empty($data['buy_qty']) || empty($data['free_qty']) ? ['buy_qty' => 'Isi jumlah beli & gratis.'] : [],
        };
        if ($data['scope'] !== 'all' && empty($data['target_ids'])) {
            $errors['target_ids'] = $data['scope'] === 'categories' ? 'Pilih minimal satu kategori.' : 'Pilih minimal satu produk.';
        }
        if ($data['scope'] !== 'all' && ! empty($data['target_ids'])) {
            $table = $data['scope'] === 'categories' ? 'categories' : 'products';
            $found = DB::table($table)->whereIn('id', $data['target_ids'])->count();
            if ($found !== count($data['target_ids'])) {
                $errors['target_ids'] = 'Ada kategori/produk yang tidak ditemukan.';
            }
        }
        if ($errors !== []) {
            throw ValidationException::withMessages($errors);
        }

        $promotion ??= new Promotion;
        $before = $promotion->exists ? PromotionService::presentPromotion($promotion) : null;
        $promotion->fill([
            ...$data,
            'value' => $data['type'] === 'bogo' ? 0 : (int) $data['value'],
            'buy_qty' => $data['type'] === 'bogo' ? $data['buy_qty'] : 0,
            'free_qty' => $data['type'] === 'bogo' ? $data['free_qty'] : 0,
            'target_ids' => $data['scope'] === 'all' ? null : array_values($data['target_ids']),
            'days' => empty($data['days']) || count($data['days']) === 7 ? null : array_values(array_map('intval', $data['days'])),
            'active' => $data['active'] ?? true,
        ])->save();
        Audit::record($before ? 'promotion.updated' : 'promotion.created', $promotion, $before, PromotionService::presentPromotion($promotion));

        return response()->json(['data' => PromotionService::presentPromotion($promotion)], $before ? 200 : 201);
    }

    public function saveVoucher(Request $request, ?Voucher $voucher = null): JsonResponse
    {
        $this->guard();
        $request->merge(['code' => mb_strtoupper(trim((string) $request->input('code')))]);
        $data = $request->validate([
            'code' => ['required', 'string', 'regex:/^[A-Z0-9_-]{3,20}$/',
                Rule::unique('vouchers', 'code')->where('tenant_id', $request->user()->tenant_id)->ignore($voucher?->id)],
            'type' => ['required', Rule::in(['percent', 'amount'])],
            'value' => ['required', 'integer', 'min:1', 'max:100000000'],
            'max_discount' => ['nullable', 'integer', 'min:1', 'max:100000000'],
            'min_spend' => ['nullable', 'integer', 'min:0', 'max:1000000000'],
            'starts_on' => ['nullable', 'date_format:Y-m-d'],
            'ends_on' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:starts_on'],
            'usage_limit' => ['nullable', 'integer', 'min:1', 'max:1000000'],
            'active' => ['sometimes', 'boolean'],
        ], [
            'code.regex' => 'Kode 3–20 huruf/angka (boleh - dan _), tanpa spasi.',
            'code.unique' => 'Kode voucher sudah dipakai.',
        ]);
        if ($data['type'] === 'percent' && $data['value'] > 10000) {
            throw ValidationException::withMessages(['value' => 'Potongan persen harus 1–100%.']);
        }

        $voucher ??= new Voucher;
        $before = $voucher->exists ? PromotionService::presentVoucher($voucher) : null;
        $voucher->fill([
            ...$data,
            'max_discount' => $data['type'] === 'percent' ? ($data['max_discount'] ?? null) : null,
            'min_spend' => $data['min_spend'] ?? 0,
            'active' => $data['active'] ?? true,
        ])->save();
        Audit::record($before ? 'voucher.updated' : 'voucher.created', $voucher, $before, PromotionService::presentVoucher($voucher));

        return response()->json(['data' => PromotionService::presentVoucher($voucher, $this->promotions->usage($voucher))], $before ? 200 : 201);
    }

    /** Kasir: cek kode voucher → syarat & potongannya (untuk dihitung di tablet). */
    public function check(Request $request): JsonResponse
    {
        $data = $request->validate(['code' => ['required', 'string', 'max:20']]);
        $voucher = $this->promotions->voucher($data['code']);

        return response()->json(['data' => PromotionService::presentVoucher($voucher)]);
    }

    private function guard(): void
    {
        abort_unless($this->promotions->enabled(), 403, 'Fitur promo & voucher tidak aktif untuk kedai ini.');
    }
}
