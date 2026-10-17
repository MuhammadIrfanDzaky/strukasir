<?php

namespace App\Services;

use App\Mail\ShiftReportMail;
use App\Models\Device;
use App\Models\Outlet;
use App\Models\Shift;
use App\Models\Tenant;
use App\Models\TenantSetting;
use App\Models\User;
use App\Support\PhoneNumber;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Throwable;

/**
 * Laporan tutup shift untuk owner: teks ringkas (WhatsApp & email) berisi penjualan shift, metode bayar,
 * kas keluar/masuk, selisih kas, void, produk terlaris, dan total hari itu dari semua tablet.
 */
class ShiftReportService
{
    private const DAYS = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

    /**
     * Data laporan shift (dipakai teks WhatsApp/email dan tampilan email bergrafik).
     *
     * @return array<string, mixed>
     */
    public function data(Shift $shift): array
    {
        $summary = app(ShiftService::class)->summary($shift);
        $tenant = Tenant::query()->findOrFail($shift->tenant_id);
        $tz = $tenant->timezone ?: 'Asia/Jakarta';
        $names = User::query()->whereIn('id', array_filter([$shift->opened_by, $shift->closed_by]))->pluck('name', 'id');
        $outlets = Outlet::query()->where('active', true)->count();
        $opened = $shift->opened_at->copy()->setTimezone($tz);
        $closed = $shift->closed_at?->copy()->setTimezone($tz);
        $m = $summary['by_method'];

        $dayQuery = fn () => DB::table('orders')->where('status', 'paid')->where('business_date', $opened->toDateString())
            ->selectRaw('count(*) as n, coalesce(sum(grand_total), 0) as total');
        $day = $dayQuery()->first();
        $dayOutlet = $outlets > 1 ? $dayQuery()->where('outlet_id', $shift->outlet_id)->first() : null;
        // QRIS statis dikonfirmasi kasir: jumlah transaksi & referensi untuk dicocokkan dengan mutasi merchant.
        $qris = DB::table('payments')->join('orders', 'orders.id', '=', 'payments.order_id')
            ->where('payments.shift_id', $shift->id)->where('payments.kind', 'payment')->where('payments.method', 'qris')
            ->where('orders.status', 'paid')->orderBy('payments.confirmed_at')
            ->get(['payments.amount', 'payments.reference']);
        $low = app(InventoryService::class)->enabled() ? app(InventoryService::class)->lowStock($shift->outlet_id) : collect();

        return [
            'shop' => TenantSetting::query()->value('receipt_name') ?: $tenant->name,
            'outlet' => $outlets > 1 ? Outlet::query()->whereKey($shift->outlet_id)->value('name') : null,
            'day' => self::DAYS[$opened->dayOfWeekIso - 1],
            'date' => $opened->format('d/m/Y'),
            'device' => Device::query()->whereKey($shift->device_id)->value('code'),
            'from' => $opened->format('H:i'),
            'to' => $closed?->format('H:i'),
            'opened_by' => $names[$shift->opened_by] ?? '-',
            'closed_by' => $shift->closed_by && $shift->closed_by !== $shift->opened_by ? ($names[$shift->closed_by] ?? '-') : null,
            'sales' => array_sum($m),
            'orders' => (int) $summary['paid_orders'],
            'methods' => collect(['cash' => 'Tunai', 'qris' => 'QRIS', 'debit' => 'Debit', 'credit' => 'Kasbon'])
                ->filter(fn ($label, $key) => ($m[$key] ?? 0) !== 0)
                ->map(fn ($label, $key) => ['label' => $label, 'amount' => (int) $m[$key]])->values()->all(),
            'qris' => $qris->isEmpty() ? null : [
                'count' => $qris->count(),
                'total' => (int) $qris->sum('amount'),
                'without_reference' => $qris->filter(fn ($p) => trim((string) $p->reference) === '')->count(),
                'references' => $qris->pluck('reference')->filter(fn ($r) => trim((string) $r) !== '')->take(20)->values()->all(),
            ],
            'cash_out' => (int) $summary['cash_out'],
            'cash_in' => (int) $summary['cash_extra_in'],
            'credit_repaid_cash' => (int) ($summary['credit_repaid_cash'] ?? 0),
            'cash' => $shift->closed_at === null ? null : [
                'expected' => (int) $shift->expected_cash, 'counted' => (int) $shift->counted_cash, 'diff' => (int) $shift->difference,
            ],
            'voids' => DB::table('orders')->where('shift_id', $shift->id)->where('status', 'void')->count(),
            'top' => DB::table('order_items')->join('orders', 'orders.id', '=', 'order_items.order_id')
                ->where('orders.shift_id', $shift->id)->where('orders.status', 'paid')
                ->groupBy('order_items.name')->orderByRaw('sum(order_items.qty) desc')->limit(5)
                ->selectRaw('order_items.name, sum(order_items.qty) as qty')->get()
                ->map(fn ($r) => ['name' => $r->name, 'qty' => (int) $r->qty])->all(),
            'note' => $shift->note,
            'low_stock' => $low->map(fn ($i) => ['name' => $i->name, 'qty' => self::qty((float) $i->stock).' '.$i->unit])->values()->all(),
            'day_outlet' => $dayOutlet === null ? null : ['total' => (int) $dayOutlet->total, 'n' => (int) $dayOutlet->n],
            'day_total' => ['total' => (int) $day->total, 'n' => (int) $day->n],
            'all_label' => $outlets > 1 ? 'semua outlet' : 'semua tablet',
        ];
    }

    public function text(Shift $shift): string
    {
        return self::textFrom($this->data($shift));
    }

    /** @param array<string, mixed> $d hasil data() */
    public static function textFrom(array $d): string
    {
        $methods = collect($d['methods'])->map(fn ($x) => "{$x['label']} ".self::rp($x['amount']))->implode(' · ');
        $lines = [
            "*Laporan shift {$d['shop']}*".($d['outlet'] ? " · {$d['outlet']}" : ''),
            "{$d['day']}, {$d['date']} · Tablet {$d['device']}",
            "Jam {$d['from']}–".($d['to'] ?? 'sekarang').' · '.$d['opened_by'].($d['closed_by'] ? " → {$d['closed_by']}" : ''),
            '',
            '*Penjualan: '.self::rp($d['sales']).'* ('.$d['orders'].' transaksi)',
        ];
        if ($methods !== '') {
            $lines[] = $methods;
        }
        if (($d['qris'] ?? null) !== null) {
            $q = $d['qris'];
            $lines[] = "Cocokkan QRIS: {$q['count']} transaksi ".self::rp($q['total']).' dengan mutasi aplikasi merchant'
                .($q['references'] !== [] ? ' (ref '.implode(', ', $q['references']).')' : '')
                .($q['without_reference'] > 0 ? " · {$q['without_reference']} tanpa ref" : '');
        }
        if ($d['cash_out'] > 0 || $d['cash_in'] > 0) {
            $lines[] = 'Kas keluar '.self::rp($d['cash_out']).' · kas masuk '.self::rp($d['cash_in']);
        }
        if ($d['credit_repaid_cash'] > 0) {
            $lines[] = 'Pelunasan kasbon tunai '.self::rp($d['credit_repaid_cash']);
        }
        if ($d['cash'] !== null) {
            $diff = $d['cash']['diff'];
            $lines[] = 'Kas seharusnya '.self::rp($d['cash']['expected']).' · dihitung '.self::rp($d['cash']['counted'])
                .' · '.($diff === 0 ? 'cocok ✅' : ($diff > 0 ? 'LEBIH ' : 'KURANG ').self::rp(abs($diff)).' ⚠️');
        }
        if ($d['voids'] > 0) {
            $lines[] = "Void: {$d['voids']} order";
        }
        if ($d['top'] !== []) {
            $lines[] = 'Terlaris: '.collect($d['top'])->take(3)->map(fn ($t) => "{$t['name']} {$t['qty']}×")->implode(', ');
        }
        if ($d['note']) {
            $lines[] = "Catatan: {$d['note']}";
        }
        if ($d['low_stock'] !== []) {
            $low = collect($d['low_stock']);
            $lines[] = 'Stok menipis: '.$low->take(8)->map(fn ($i) => "{$i['name']} {$i['qty']}")->implode(', ')
                .($low->count() > 8 ? ' (+'.($low->count() - 8).')' : '');
        }
        $lines[] = '';
        if ($d['day_outlet'] !== null) {
            $lines[] = "Total hari ini {$d['outlet']}: ".self::rp($d['day_outlet']['total']).' · '.$d['day_outlet']['n'].' transaksi';
        }
        $lines[] = "Total hari ini ({$d['all_label']}): ".self::rp($d['day_total']['total']).' · '.$d['day_total']['n'].' transaksi';

        return implode("\n", $lines);
    }

    /** Nomor WhatsApp owner untuk laporan (pengaturan, atau no HP saat daftar). */
    public function ownerWhatsApp(): ?string
    {
        $setting = TenantSetting::query()->value('report_whatsapp');
        $phone = $setting ?? Tenant::query()->whereKey(app(TenantContext::class)->id())->value('phone');

        return PhoneNumber::normalize($phone);
    }

    /** Kirim email laporan ke owner (email terverifikasi) setelah respons; gagal kirim tidak mengganggu kasir. */
    public function emailOwner(Shift $shift): void
    {
        $tenantId = $shift->tenant_id;
        // Dijalankan di proses yang sama setelah respons terkirim (tanpa antrean/serialisasi).
        app()->terminating(function () use ($tenantId, $shift) {
            try {
                app(TenantContext::class)->run($tenantId, function () use ($shift) {
                    if (! TenantSetting::query()->value('report_email')) {
                        return;
                    }
                    $owners = User::query()->where('role', 'owner')->where('active', true)
                        ->whereNotNull('email')->whereNotNull('email_verified_at')->get();
                    $data = $this->data($shift->fresh());
                    $text = self::textFrom($data);
                    $subject = 'Laporan shift '.Carbon::parse($shift->opened_at)->setTimezone(Tenant::query()->whereKey($shift->tenant_id)->value('timezone') ?: 'Asia/Jakarta')->format('d/m/Y H:i');
                    foreach ($owners as $owner) {
                        Mail::to($owner->email)->send(new ShiftReportMail($subject, $text, $data));
                    }
                });
            } catch (Throwable $e) {
                Log::warning('Laporan shift gagal dikirim ke email owner', ['shift_id' => $shift->id, 'error' => $e->getMessage()]);
            }
        });
    }

    private static function rp(int $amount): string
    {
        return 'Rp'.number_format($amount, 0, ',', '.');
    }

    /** 1.500 / 2,5 (tanpa nol di belakang koma). */
    private static function qty(float $qty): string
    {
        return rtrim(rtrim(number_format($qty, 3, ',', '.'), '0'), ',');
    }
}
