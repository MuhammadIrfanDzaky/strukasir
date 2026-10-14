<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

// Tagihan paket yang belum terkonfirmasi (webhook tidak sampai) dicek ke gateway. Jalan di service `scheduler`.
Schedule::command('pos:sync-payments')->everyFiveMinutes()->withoutOverlapping();

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');
