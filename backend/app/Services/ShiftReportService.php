<?php

namespace App\Services;

use App\Mail\ShiftReportMail;
use App\Models\Device;
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

    public function text(Shift $shift): string
    {
        $summary = app(ShiftService::class)->summary($shift);
        $tenant = Tenant::query()->findOrFail($shift->tenant_id);
        $tz = $tenant->timezone ?: 'Asia/Jakarta';
        $shop = TenantSetting::query()->value('receipt_name') ?: $tenant->name;
        $names = User::query()->whereIn('id', array_filter([$shift->opened_by, $shift->closed_by]))->pluck('name', 'id');
        $device = Device::query()->whereKey($shift->device_id)->value('code');
        $opened = $shift->opened_at->copy()->setTimezone($tz);
        $closed = $shift->closed_at?->copy()->setTimezone($tz);
        $m = $summary['by_method'];
        $sales = array_sum($m);

        $top = DB::table('order_items')->join('orders', 'orders.id', '=', 'order_items.order_id')
            ->where('orders.shift_id', $shift->id)->where('orders.status', 'paid')
            ->groupBy('order_items.name')->orderByRaw('sum(order_items.qty) desc')->limit(3)
            ->selectRaw('order_items.name, sum(order_items.qty) as qty')->get()
            ->map(fn ($r) => "{$r->name} {$r->qty}×")->implode(', ');
        $voids = DB::table('orders')->where('shift_id', $shift->id)->where('status', 'void')->count();
        $day = DB::table('orders')->where('status', 'paid')->where('business_date', $opened->toDateString())
            ->selectRaw('count(*) as n, coalesce(sum(grand_total), 0) as total')->first();

        $methods = collect(['cash' => 'Tunai', 'qris' => 'QRIS', 'debit' => 'Debit', 'credit' => 'Kasbon'])
            ->filter(fn ($label, $key) => ($m[$key] ?? 0) !== 0)
            ->map(fn ($label, $key) => "{$label} ".self::rp($m[$key]))->implode(' · ');

        $lines = [
            "*Laporan shift {$shop}*",
            self::DAYS[$opened->dayOfWeekIso - 1].', '.$opened->format('d/m/Y')." · Tablet {$device}",
            'Jam '.$opened->format('H:i').'–'.($closed?->format('H:i') ?? 'sekarang')
                .' · '.($names[$shift->opened_by] ?? '-').($shift->closed_by && $shift->closed_by !== $shift->opened_by ? ' → '.($names[$shift->closed_by] ?? '-') : ''),
            '',
            '*Penjualan: '.self::rp($sales).'* ('.$summary['paid_orders'].' transaksi)',
        ];
        if ($methods !== '') {
            $lines[] = $methods;
        }
        if ($summary['cash_out'] > 0 || $summary['cash_extra_in'] > 0) {
            $lines[] = 'Kas keluar '.self::rp($summary['cash_out']).' · kas masuk '.self::rp($summary['cash_extra_in']);
        }
        if (($summary['credit_repaid_cash'] ?? 0) > 0) {
            $lines[] = 'Pelunasan kasbon tunai '.self::rp($summary['credit_repaid_cash']);
        }
        if ($shift->closed_at !== null) {
            $diff = (int) $shift->difference;
            $lines[] = 'Kas seharusnya '.self::rp((int) $shift->expected_cash).' · dihitung '.self::rp((int) $shift->counted_cash)
                .' · '.($diff === 0 ? 'cocok ✅' : ($diff > 0 ? 'LEBIH ' : 'KURANG ').self::rp(abs($diff)).' ⚠️');
        }
        if ($voids > 0) {
            $lines[] = "Void: {$voids} order";
        }
        if ($top !== '') {
            $lines[] = "Terlaris: {$top}";
        }
        if ($shift->note) {
            $lines[] = "Catatan: {$shift->note}";
        }
        $lines[] = '';
        $lines[] = 'Total hari ini (semua tablet): '.self::rp((int) $day->total).' · '.$day->n.' transaksi';

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
                    $text = $this->text($shift->fresh());
                    $subject = 'Laporan shift '.Carbon::parse($shift->opened_at)->setTimezone(Tenant::query()->whereKey($shift->tenant_id)->value('timezone') ?: 'Asia/Jakarta')->format('d/m/Y H:i');
                    foreach ($owners as $owner) {
                        Mail::to($owner->email)->send(new ShiftReportMail($subject, $text));
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
}
