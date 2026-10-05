# Load test kasir

Mengukur kapasitas server: berapa transaksi per detik yang masih nyaman sebelum antre.
Satu transaksi = simpan order (1–3 item) + bayar tunai; 10% transaksi juga memuat menu.

| File | Isi |
|---|---|
| `setup.php` | Membuat N kedai uji `lt-1 … lt-N` (kasir, tablet, token, shift terbuka, 5 produk) → `/tmp/tokens.json` |
| `k6.js` | Skenario k6, laju tetap `RATE` order/detik selama 60 detik |
| `run.sh` | Menjalankan k6 di jaringan Docker yang sama dengan `app` pada beberapa laju + mencatat CPU/RAM |
| `cleanup.php` | **Menghapus semua kedai uji `lt-*`**. Wajib dijalankan setelah uji di produksi |
| `limits.yml` | (lokal) mengunci app + db ke 2 core & ±2 GB RAM untuk mensimulasikan VPS kecil |

`tokens.json` berisi token login kedai uji. Sudah di-gitignore; hapus setelah selesai.

## Di VPS produksi

Jalankan di luar jam operasional kedai. Uji ini memakan CPU penuh selama beberapa menit.

```bash
C="docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env"
docker cp tools/loadtest/setup.php berrybrew-app-1:/tmp/setup.php
docker cp tools/loadtest/cleanup.php berrybrew-app-1:/tmp/cleanup.php
$C exec app php /tmp/setup.php 100
docker cp berrybrew-app-1:/tmp/tokens.json tools/loadtest/tokens.json

tools/loadtest/run.sh berrybrew pos-berrybrew.my.id 5 10 20

$C exec app php /tmp/cleanup.php          # WAJIB: hapus kedai uji
rm tools/loadtest/tokens.json
```

## Di laptop (simulasi VPS 2 vCPU / 2 GB)

```bash
L="docker compose -f deploy/docker-compose.prod.yml -f deploy/docker-compose.local-test.yml -f tools/loadtest/limits.yml --env-file deploy/.env.local-test -p berrybrew-load"
# deploy/.env.local-test: SERVER_NAME="localhost, app.localhost"; deploy/backup.env boleh dummy
$L up -d --build && $L exec app php artisan migrate --force
# lalu setup.php seperti di atas (container berrybrew-load-app-1), kemudian:
tools/loadtest/run.sh berrybrew-load app.localhost 5 10 20 40
$L down -v
```

Di Git Bash (Windows) jalankan dengan `MSYS_NO_PATHCONV=1` agar path `/tmp/...` tidak diubah.

## Hasil

### 2026-10-05 — laptop, app + db dikunci 2 core, RAM ±2 GB, 100 kedai

| Laju | Simpan order p95 | Bayar p95 | Error | CPU app+db | RAM app+db |
|---|---|---|---|---|---|
| 5/detik | 118 ms | 90 ms | 0% | ~72% | ~114 MB |
| 10/detik | 97 ms | 81 ms | 0% | ~119% | ~117 MB |
| 20/detik | 6,2 s | 6,1 s | 0% (antre) | ~188% | ~137 MB |
| 40/detik | 12,4 s | 12,4 s | 0% (antre) | ~200% | ~163 MB |

- **Batas: CPU**, maksimum ±15 order/detik. RAM bukan masalah.
- **Ukuran data**: ±2 KB per order (termasuk item, pembayaran, audit). Kedai 200 order/hari ≈ 150 MB/tahun.
- **Perkiraan kapasitas VPS 2 vCPU / 2 GB**: ±100–200 kedai kecil. Kedai ramai saat jam sibuk ≈ 1 order/menit;
  margin 3–4× karena vCPU cloud biasanya lebih lambat dari CPU laptop.
- **Ulangi di VPS asli** untuk angka pasti, lalu tambahkan hasilnya di sini.
