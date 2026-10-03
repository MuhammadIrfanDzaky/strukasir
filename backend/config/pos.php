<?php

return [
    /*
     * Versi app tablet. `min_version` di atas versi terpasang → app menolak dipakai sampai diperbarui
     * (mis. ada perubahan API yang tidak kompatibel atau perbaikan keamanan).
     */
    'app' => [
        'latest_version' => env('POS_APP_LATEST_VERSION', '1.0.0'),
        'min_version' => env('POS_APP_MIN_VERSION', '1.0.0'),
        'download_url' => env('POS_APP_DOWNLOAD_URL'),
    ],
];
