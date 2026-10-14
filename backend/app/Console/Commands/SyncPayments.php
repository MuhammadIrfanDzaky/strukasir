<?php

namespace App\Console\Commands;

use App\Services\Payments\SubscriptionCheckout;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Throwable;

/**
 * Cocokkan tagihan paket yang masih menunggu dengan Mayar (dijadwalkan tiap 5 menit). Cadangan bila
 * webhook tidak sampai dan owner sudah menutup layar bayar: paket tetap aktif setelah lunas.
 */
class SyncPayments extends Command
{
    protected $signature = 'pos:sync-payments {--hours=48 : Hanya tagihan yang dibuat dalam N jam terakhir}';

    protected $description = 'Cek status tagihan paket yang masih menunggu ke payment gateway';

    public function handle(SubscriptionCheckout $checkout): int
    {
        if (! $checkout->enabled()) {
            return self::SUCCESS;
        }
        $pending = DB::table('subscription_invoices')->where('status', 'pending')
            ->where('created_at', '>', now()->subHours((int) $this->option('hours')))
            ->orderBy('created_at')->limit(200)->get();

        $paid = 0;
        foreach ($pending as $invoice) {
            try {
                $paid += $checkout->sync($invoice)->status === 'paid' ? 1 : 0;
            } catch (Throwable $e) {
                report($e); // satu tagihan gagal tidak menghentikan yang lain
            }
        }
        // Tagihan lewat batas waktu yang tidak pernah dibayar → ditutup.
        $expired = DB::table('subscription_invoices')->where('status', 'pending')
            ->where('expires_at', '<', now()->subHour())->update(['status' => 'expired', 'updated_at' => now()]);

        $this->info("Dicek {$pending->count()}, lunas {$paid}, kedaluwarsa {$expired}.");

        return self::SUCCESS;
    }
}
