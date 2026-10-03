#!/bin/sh
# Backup penuh database ke R2 (rclone remote "r2", dikonfigurasi lewat env RCLONE_CONFIG_R2_*).
# Memakai superuser: pg_dump oleh role app akan terhalang Row-Level Security (FORCE).
set -eu
STAMP=$(date +%Y%m%d-%H%M%S)
FILE="/tmp/berrybrew-$STAMP.dump"
DEST="r2:$R2_BUCKET/postgres"

PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h db -U postgres -d berrybrew -Fc -f "$FILE"
rclone copyto "$FILE" "$DEST/berrybrew-$STAMP.dump"
rclone delete --min-age "${BACKUP_RETENTION_DAYS:-30}d" "$DEST/"
SIZE=$(du -h "$FILE" | cut -f1)
rm -f "$FILE"
echo "[backup] OK berrybrew-$STAMP.dump ($SIZE)"

# Opsional: ping monitor (mis. healthchecks.io) agar backup yang GAGAL ketahuan.
if [ -n "${BACKUP_HEARTBEAT_URL:-}" ]; then wget -q -O /dev/null "$BACKUP_HEARTBEAT_URL" || true; fi
