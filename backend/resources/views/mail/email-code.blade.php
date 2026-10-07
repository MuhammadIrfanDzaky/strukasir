Halo {{ $name }},

@if ($purpose === \App\Services\EmailCodes::RESET_PASSWORD)
Ada permintaan reset password akun owner Strukasir Anda. Masukkan kode ini di aplikasi:
@else
Masukkan kode ini di aplikasi Strukasir untuk memverifikasi email Anda:
@endif

    {{ $code }}

Kode berlaku {{ $minutes }} menit dan hanya bisa dipakai sekali.
Jangan berikan kode ini kepada siapa pun, termasuk yang mengaku dari Strukasir.

Bila Anda tidak memintanya, abaikan email ini. Akun Anda tetap aman.

— Strukasir
