#!/bin/sh
# Pulihkan backup dari remote "backup" ke database TERPISAH (default berrybrew_restore_test) lalu tampilkan
# jumlah baris tabel penting. Menimpa database produksi butuh TARGET=berrybrew CONFIRM=yes.
#
#   restore.sh                 → backup terbaru  → berrybrew_restore_test
#   restore.sh <nama-file>     → file tertentu  → berrybrew_restore_test
set -eu
TARGET="${TARGET:-berrybrew_restore_test}"
SRC="backup:$BACKUP_PATH"
NAME="${1:-$(rclone lsf "$SRC/" | sort | tail -n 1)}"
[ -n "$NAME" ] || { echo "[restore] Tidak ada backup di $SRC"; exit 1; }

if [ "$TARGET" = "berrybrew" ] && [ "${CONFIRM:-}" != "yes" ]; then
  echo "[restore] Menimpa database produksi butuh CONFIRM=yes"; exit 1
fi

export PGPASSWORD="$POSTGRES_PASSWORD"
rclone copyto "$SRC/$NAME" /tmp/restore.dump
psql -h db -U postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS \"$TARGET\"" -c "CREATE DATABASE \"$TARGET\" OWNER berrybrew_app"
pg_restore -h db -U postgres -d "$TARGET" --exit-on-error /tmp/restore.dump
rm -f /tmp/restore.dump

echo "[restore] $NAME → $TARGET"
psql -h db -U postgres -d "$TARGET" -At -c "
  select 'tenants', count(*) from tenants union all
  select 'users', count(*) from users union all
  select 'products', count(*) from products union all
  select 'orders', count(*) from orders union all
  select 'payments', count(*) from payments union all
  select 'audit_logs', count(*) from audit_logs"
