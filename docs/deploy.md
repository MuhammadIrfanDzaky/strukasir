# Panduan Deploy Produksi

Target: 1 VM Oracle Cloud **Always Free** (ARM Ampere) + domain `.my.id` + Cloudflare R2 untuk backup.
Semua yang ditandai **(akun)** harus Anda buat sendiri. Kredensialnya simpan di password manager
yang juga bisa diakses orang kedua yang dipercaya (bus factor, kompetensi #49).

Paket deploy ada di `deploy/` dan sudah diuji lokal (HTTPS, migrasi, alur kasir, backup + restore):

| File | Isi |
|---|---|
| `deploy/docker-compose.prod.yml` | `app` (FrankenPHP + Caddy, HTTPS otomatis), `db` (PostgreSQL 17), `backup` (pg_dump harian → R2) |
| `deploy/Dockerfile` | Image API produksi (tanpa dev dependency, opcache, `APP_DEBUG=false`) |
| `deploy/Caddyfile` | HTTPS + redirect HTTP→HTTPS + HSTS |
| `deploy/postgres/init.sh` | Role app **non-superuser** (wajib agar Row-Level Security berlaku) |
| `deploy/backup/` | `backup.sh` (cron 03:00 WIB), `restore.sh` (pulihkan ke DB terpisah) |
| `deploy/.env.example` | Semua variabel yang perlu diisi |

---

## 1. Siapkan akun (sekali)

1. **(akun) Oracle Cloud**: daftar, lalu **upgrade ke Pay As You Go**. Selama tetap di kuota Always Free
   tagihannya Rp0, dan instance tidak direklaim karena "idle".
   - Pasang **budget alert** (mis. US$1) di *Billing → Budgets* (SEC-38).
   - Pilih home region terdekat (Singapore atau Jakarta bila tersedia) — region Always Free tidak bisa diganti setelah daftar.
2. **(akun) Domain** `.my.id`, mis. `pos-berrybrew.my.id`. Arahkan DNS ke Cloudflare (gratis).
3. **(akun) Cloudflare R2**: buat bucket `berrybrew-backup` (private), lalu buat API token
   *Object Read & Write* khusus bucket itu. Catat Account ID, Access Key, dan Secret.
4. **(opsional, gratis) healthchecks.io**: satu check harian untuk backup (`BACKUP_HEARTBEAT_URL`).
5. **(akun) UptimeRobot** (gratis): monitor HTTPS `https://<domain>/up` tiap 5 menit, dengan alert ke email/WA.

## 2. Siapkan VM

- Shape `VM.Standard.A1.Flex` (2 OCPU / 12 GB cukup), Ubuntu 24.04.
- Security list / NSG: buka **TCP 80, 443** (dan UDP 443). SSH 22 hanya dari IP Anda.
- Di VM:

```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2 git
sudo usermod -aG docker $USER   # login ulang setelah ini
sudo iptables -I INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT && sudo netfilter-persistent save
```

- DNS: buat record **A** `pos-berrybrew.my.id → <IP publik VM>`. Untuk record ini, matikan proxy
  Cloudflare (ikon awan abu-abu, *DNS only*), supaya Caddy bisa menerbitkan sertifikat sendiri.

## 3. Deploy pertama

```bash
git clone https://github.com/MuhammadIrfanDzaky/berrybrew-pos.git && cd berrybrew-pos
cp deploy/.env.example deploy/.env && nano deploy/.env
```

Isi `deploy/.env`:
- `SERVER_NAME` dan `APP_URL`: domain Anda.
- `APP_KEY`: buat dengan `docker run --rm php:8.4-cli php -r "echo 'base64:'.base64_encode(random_bytes(32)), PHP_EOL;"`.
- `POSTGRES_PASSWORD` dan `APP_DB_PASSWORD`: acak, **hanya huruf & angka** (`openssl rand -base64 24 | tr -dc A-Za-z0-9`).
- Variabel `R2_*` dan `BACKUP_HEARTBEAT_URL`.

```bash
C="docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env"
$C up -d --build
$C exec app php artisan migrate --force
$C exec app php artisan pos:create-tenant berrybrew "BerryBrew" --owner-email=<email-owner>
```

Command terakhir menampilkan **password & PIN owner sekali saja**. Serahkan langsung ke owner.

Cek hasilnya:

```bash
curl -I https://pos-berrybrew.my.id/up        # 200 + Strict-Transport-Security
$C exec backup backup.sh                      # [backup] OK ...
$C exec backup restore.sh                     # pulihkan ke berrybrew_restore_test + jumlah baris
```

## 4. Update (deploy berikutnya)

```bash
git pull
$C up -d --build app
$C exec app php artisan migrate --force
```

**Rollback**: `git checkout <commit-sebelumnya> && $C up -d --build app`. Migrasi di proyek ini hanya
menambah (expand). Kalau sebuah rilis membawa migrasi yang menghapus kolom, pulihkan dulu dari backup
ke DB terpisah dan periksa sebelum rollback.

## 5. Uji restore (wajib sebelum go-live, lalu tiap bulan)

```bash
$C exec backup restore.sh                         # backup terbaru → berrybrew_restore_test
$C exec db psql -U postgres -d berrybrew -At -c "select count(*) from orders"   # bandingkan
```

Jumlah baris harus sama dengan produksi pada saat backup dibuat. Menimpa produksi (hanya saat bencana):
`$C exec -e TARGET=berrybrew -e CONFIRM=yes backup restore.sh <nama-file>`.

## 6. Rilis app tablet

1. Sekali saja, buat keystore. Simpan file & passwordnya di password manager; **kalau hilang, app tidak
   bisa di-update** dan harus dipasang ulang:
   ```bash
   keytool -genkey -v -keystore berrybrew-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias berrybrew
   ```
   Lalu buat `app/android/key.properties` (di-ignore git):
   ```
   storeFile=../../berrybrew-release.jks
   storePassword=...
   keyAlias=berrybrew
   keyPassword=...
   ```
2. Naikkan `version:` di `app/pubspec.yaml` (mis. `1.0.1+2`), lalu:
   ```bash
   cd app && flutter build apk --release --split-per-abi
   ```
3. Unggah `app-armeabi-v7a-release.apk` (tablet TablePC) ke tempat unduhan (mis. Google Drive dengan
   link publik). Isi `POS_APP_DOWNLOAD_URL` dan `POS_APP_LATEST_VERSION` di `deploy/.env`.
4. Kalau versi lama **harus** berhenti dipakai (perubahan API / keamanan), naikkan juga
   `POS_APP_MIN_VERSION`, lalu `$C up -d app`. Tablet dengan versi lebih lama akan diblokir sampai di-update.

## 7. Administrasi

| Kebutuhan | Perintah |
|---|---|
| Kedai baru | `$C exec app php artisan pos:create-tenant <kode> "<Nama>" --owner-email=<email>` |
| Owner lupa password / PIN | `$C exec app php artisan pos:reset-owner-password <email> --pin` |
| Log aplikasi | `$C logs -f app` |
| Log backup | `$C logs backup` |

## 8. Retensi & penghapusan data (offboarding kedai)

- **Selama berlangganan**: semua data transaksi disimpan. Backup harian disimpan **30 hari** di R2.
- **Kedai berhenti berlangganan**:
  1. Ekspor dan serahkan datanya ke klien:
     `$C exec app php artisan pos:export-tenant <kode>` (JSON tanpa password/PIN/token,
     tersimpan di `storage/app/private/exports/` di dalam container). Salin keluar dengan
     `$C cp app:/app/storage/app/private/exports ./exports`.
  2. Hapus permanen: `$C exec app php artisan pos:delete-tenant <kode> --confirm=<kode>`.
     Kedai lain tidak tersentuh, dan jejak penghapusan tercatat di log server.
  3. Data masih ada di backup lama sampai masa retensi 30 hari habis, lalu hilang sepenuhnya.
