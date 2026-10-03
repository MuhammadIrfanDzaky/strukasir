#!/bin/sh
# Dijalankan sekali saat volume Postgres pertama kali dibuat.
# App memakai role NON-superuser agar Row-Level Security benar-benar berlaku.
set -e
psql -v ON_ERROR_STOP=1 -v pw="$APP_DB_PASSWORD" --username "$POSTGRES_USER" <<'EOSQL'
CREATE ROLE berrybrew_app LOGIN PASSWORD :'pw' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE berrybrew OWNER berrybrew_app;
EOSQL
