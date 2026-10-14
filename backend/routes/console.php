<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

// Tagihan paket yang belum terkonfirmasi (webhook tidak sampai) dicek ke gateway. Jalan di service `scheduler`.
Schedule::command('pos:sync-payments')->everyFiveMinutes()->withoutOverlapping();
// Email pengingat paket (H-3, H-1, sudah habis) setiap pagi.
Schedule::command('pos:plan-reminders')->dailyAt('09:00')->timezone('Asia/Jakarta')->withoutOverlapping();

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');
