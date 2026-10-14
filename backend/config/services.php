<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],


    // Payment gateway paket langganan (Mayar invoice). Kunci kosong = pembayaran online nonaktif (aktivasi manual).
    'mayar' => [
        'api_key' => env('MAYAR_API_KEY'),
        'sandbox' => (bool) env('MAYAR_SANDBOX', true),
        'webhook_token' => env('MAYAR_WEBHOOK_TOKEN'),
        // Batasi ke QRIS (potongan termurah). Kosongkan untuk semua metode yang aktif di Mayar.
        'payment_method' => env('MAYAR_PAYMENT_METHOD', 'qris'),
        'expiry_minutes' => (int) env('MAYAR_EXPIRY_MINUTES', 30),
    ],

];
