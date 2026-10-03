#!/bin/sh
set -e
# Cache konfigurasi/route saat start (env produksi sudah tersedia di sini, bukan saat build).
php artisan config:cache
php artisan route:cache
php artisan event:cache
exec "$@"
