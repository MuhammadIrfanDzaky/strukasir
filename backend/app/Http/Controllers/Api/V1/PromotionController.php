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
    /** Diskon %, potongan Rp/item, harga spesial, beli banyak (diskon %), beli X gratis Y, paket. */
    public const TYPES = ['percent', 'amount', 'price', 'min_qty', 'bogo', 'bundle'];

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
        // Aplikasi lama mengirim satu rentang (start_time/end_time) → jadikan daftar rentang.
        if (! $request->has('times') && $request->filled('start_time')) {
            $request->merge(['times' => [['start' => $request->input('start_time'), 'end' => $request->input('end_time')]]]);
        }
        $data = $request->validate([
            'name' => ['required', 'string', 'max:40', 'regex:/\S/'],
            'type' => ['required', Rule::in(self::TYPES)],
            'value' => ['nullable', 'integer', 'min:0', 'max:100000000'],
            'buy_qty' => ['nullable', 'integer', 'min:1', 'max:50'],
            'free_qty' => ['nullable', 'integer', 'min:1', 'max:50'],
            'scope' => ['required', Rule::in(['all', 'categories', 'products'])],
            'target_ids' => ['nullable', 'array', 'max:100'],
            'target_ids.*' => ['uuid', 'distinct'],
            'days' => ['nullable', 'array', 'max:7'],
            'days.*' => ['integer', 'between:1,7', 'distinct'],
            'times' => ['nullable', 'array', 'max:4'],
            'times.*.start' => ['required', 'date_format:H:i'],
            'times.*.end' => ['required', 'date_format:H:i'],
            'bundle_items' => ['nullable', 'array', 'max:10'],
            'bundle_items.*.product_id' => ['required', 'uuid', 'distinct'],
            'bundle_items.*.qty' => ['required', 'integer', 'min:1', 'max:20'],
            'starts_on' => ['nullable', 'date_format:Y-m-d'],
            'ends_on' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:starts_on'],
            'active' => ['sometimes', 'boolean'],
        ]);
        $type = $data['type'];
        $percentOk = ($data['value'] ?? 0) >= 1 && ($data['value'] ?? 0) <= 10000;
        $errors = match ($type) {
            'percent' => $percentOk ? [] : ['value' => 'Potongan persen harus 1–100%.'],
            'amount' => ($data['value'] ?? 0) < 1 ? ['value' => 'Isi potongan per item (Rp).'] : [],
            'price' => ! isset($data['value']) ? ['value' => 'Isi harga spesial per item (Rp).'] : [],
            'min_qty' => ($data['buy_qty'] ?? 0) < 2 ? ['buy_qty' => 'Minimal beli harus 2 item atau lebih.']
                : ($percentOk ? [] : ['value' => 'Potongan persen harus 1–100%.']),
            'bogo' => empty($data['buy_qty']) || empty($data['free_qty']) ? ['buy_qty' => 'Isi jumlah beli & gratis.'] : [],
            default => $this->bundleErrors($data),
        };
        foreach ($data['times'] ?? [] as $w) {
            if ($w['start'] === $w['end']) {
                $errors['times'] = 'Jam mulai dan selesai tidak boleh sama.';
            }
        }
        if ($type === 'bundle') {
            $data['scope'] = 'all'; // isi paket ditentukan bundle_items
        }
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
            'value' => $type === 'bogo' ? 0 : (int) $data['value'],
            'buy_qty' => in_array($type, ['bogo', 'min_qty'], true) ? $data['buy_qty'] : 0,
            'free_qty' => $type === 'bogo' ? $data['free_qty'] : 0,
            'target_ids' => $data['scope'] === 'all' ? null : array_values($data['target_ids']),
            'bundle_items' => $type === 'bundle'
                ? array_map(fn ($b) => ['product_id' => $b['product_id'], 'qty' => (int) $b['qty']], array_values($data['bundle_items'])) : null,
            'days' => empty($data['days']) || count($data['days']) === 7 ? null : array_values(array_map('intval', $data['days'])),
            'times' => empty($data['times']) ? null
                : collect($data['times'])->map(fn ($w) => ['start' => $w['start'], 'end' => $w['end']])->sortBy('start')->values()->all(),
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

    /** @return array<string, string> */
    private function bundleErrors(array $data): array
    {
        $items = $data['bundle_items'] ?? [];
        if (count($items) < 2 && array_sum(array_column($items, 'qty')) < 2) {
            return ['bundle_items' => 'Isi paket minimal 2 item.'];
        }
        $prices = DB::table('products')->whereIn('id', array_column($items, 'product_id'))->pluck('price', 'id');
        if ($prices->count() !== count($items)) {
            return ['bundle_items' => 'Ada produk paket yang tidak ditemukan.'];
        }
        $normal = array_sum(array_map(fn ($b) => $b['qty'] * $prices[$b['product_id']], $items));
        if (($data['value'] ?? 0) < 1) {
            return ['value' => 'Isi harga paket (Rp).'];
        }

        return $data['value'] >= $normal
            ? ['value' => 'Harga paket harus lebih murah dari harga normal (Rp'.number_format($normal, 0, ',', '.').').'] : [];
    }

    private function guard(): void
    {
        abort_unless($this->promotions->enabled(), 403, 'Fitur promo & voucher tidak aktif untuk kedai ini.');
    }
}
