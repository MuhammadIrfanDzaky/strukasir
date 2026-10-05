#!/bin/bash
# Jalankan k6 di jaringan Docker yang sama dengan container app, pada beberapa laju (order/detik).
#   tools/loadtest/run.sh <project-compose> <host> <rate...>
#   contoh lokal : tools/loadtest/run.sh berrybrew-load app.localhost 5 10 20
#   contoh VPS   : tools/loadtest/run.sh berrybrew pos-berrybrew.my.id 5 10 20
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"; PROJECT="$1"; HOST="$2"; shift 2
export MSYS_NO_PATHCONV=1
IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$PROJECT-app-1")
for RATE in "$@"; do
  ( sleep 30; docker stats --no-stream --format "{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}" | grep -E "$PROJECT-(app|db)-1" ) > "$DIR/stats-$RATE.txt" &
  docker run --rm --network "${PROJECT}_default" --add-host "$HOST:$IP" -v "$DIR:/scripts" \
    -e RATE="$RATE" -e HOST="$HOST" -e DURATION=60s grafana/k6 run --quiet /scripts/k6.js > "$DIR/k6-$RATE.txt" 2>&1 || true
  wait
  echo "=== $RATE order/detik"
  grep -E "ep:save|ep:pay|http_req_failed\.|dropped_iterations|^ *iterations\." "$DIR/k6-$RATE.txt" | grep -v "^http_req_duration" | sed 's/^ *//'
  cat "$DIR/stats-$RATE.txt"
done
