# Panduan Deploy Produksi

Target: **1 VPS Ubuntu 24.04** (penyedia lokal Indonesia, bayar bulanan tanpa kartu kredit) + domain
`.my.id` + penyimpanan backup di luar server (**Google Drive** atau **Cloudflare R2**).
Semua yang ditandai **(akun)** harus Anda buat sendiri. Kredensialnya simpan di password manager
yang juga bisa diakses orang kedua yang dipercaya (bus factor, kompetensi #49).

Paket deploy ada di `deploy/` dan sudah diuji lokal (HTTPS, migrasi, alur kasir, backup + restore):

| File | Isi |
|---|---|
| `deploy/docker-compose.prod.yml` | `app` (FrankenPHP + Caddy, HTTPS otomatis), `db` (PostgreSQL 17), `backup` (pg_dump harian → rclone) |
| `deploy/Dockerfile` | Image API produksi (tanpa dev dependency, opcache, `APP_DEBUG=false`) |
| `deploy/Caddyfile` | HTTPS + redirect HTTP→HTTPS + HSTS |
| `deploy/postgres/init.sh` | Role app **non-superuser** (wajib agar Row-Level Security berlaku) |
| `deploy/backup/` | `backup.sh` (cron 03:00 WIB), `restore.sh` (pulihkan ke DB terpisah) |
| `deploy/.env.example` | Variabel aplikasi & database |
| `deploy/backup.env.gdrive.example`, `deploy/backup.env.r2.example` | Tujuan backup (pilih salah satu) |

---

## 1. Siapkan akun (sekali)

1. **(akun) VPS** dari penyedia lokal yang menerima transfer bank / virtual account / QRIS / e-wallet
   (mis. IDCloudHost, Biznet Gio, DomaiNesia, Jagoan Hosting; cek harga & stok terbaru).
   - Spesifikasi cukup: **1–2 vCPU, RAM 2 GB, disk 20–40 GB SSD, Ubuntu 24.04, IP publik**, lokasi **Jakarta**.
   - Bayar bulanan dengan harga tetap → tidak ada risiko tagihan membengkak (SEC-38). Biaya masuk ke harga
     subscription/maintenance klien.
   - Pilih login **SSH key** (bukan password) bila tersedia.
2. **(akun) Domain** `.my.id`, mis. `pos-berrybrew.my.id`. Arahkan nameserver ke **Cloudflare** (gratis).
3. **(akun) Penyimpanan backup**, pilih satu:
   - **Google Drive** (gratis 15 GB, tanpa kartu). Pakai akun Google khusus bisnis/kedai.
     Ikuti langkah token di `deploy/backup.env.gdrive.example`.
   - **Cloudflare R2** (gratis 10 GB, aktivasi butuh kartu/PayPal): bucket `berrybrew-backup` (private) +
     API token *Object Read & Write* khusus bucket itu.
4. **(opsional, gratis) healthchecks.io**: satu check harian untuk backup (`BACKUP_HEARTBEAT_URL`).
5. **(akun) UptimeRobot** (gratis): monitor HTTPS `https://<domain>/up` tiap 5 menit, dengan alert ke email/WA.
6. **(akun) Sentry** (gratis, sentry.io): buat 2 proyek, **Laravel** (server) dan **Flutter** (app).
   Ambil DSN masing-masing. Aktifkan notifikasi email untuk error baru. Isi request (password, PIN,
   kode 2FA), data pribadi, dan screenshot tidak pernah dikirim.
7. **(akun) Pengirim email / SMTP** (mis. Brevo atau Mailgun, paket gratis cukup): untuk kode verifikasi
   email dan lupa password owner. Verifikasi domain pengirim (SPF/DKIM) agar email tidak masuk spam.
   Tanpa SMTP, pendaftaran tetap jalan, tapi kode tidak terkirim (owner tidak bisa reset password sendiri).

## 2. Siapkan VPS

Masuk lewat SSH, lalu:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-v2 git ufw
sudo usermod -aG docker $USER            # logout & login ulang setelah ini
sudo ufw allow OpenSSH && sudo ufw allow 80,443/tcp && sudo ufw allow 443/udp && sudo ufw enable

# Swap 2 GB: cadangan saat build image / lonjakan memori di VPS RAM 2 GB.
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swap.conf && sudo sysctl --system
```

- Bila panel penyedia punya firewall sendiri, buka juga **TCP 80, 443** (dan UDP 443).
- DNS di Cloudflare: record **A** `pos-berrybrew.my.id → <IP publik VPS>`, **proxy dimatikan**
  (ikon awan abu-abu, *DNS only*) supaya Caddy bisa menerbitkan sertifikat sendiri.
- Repo GitHub **private** → buat *deploy key* read-only di VPS:
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/berrybrew_deploy -N "" -C "vps-berrybrew"
  cat ~/.ssh/berrybrew_deploy.pub     # tempel di GitHub → repo → Settings → Deploy keys (tanpa write access)
  printf 'Host github.com\n  IdentityFile ~/.ssh/berrybrew_deploy\n' >> ~/.ssh/config
  ```

## 3. Deploy pertama

```bash
git clone git@github.com:MuhammadIrfanDzaky/strukasir.git && cd strukasir
cp deploy/.env.example deploy/.env && nano deploy/.env
cp deploy/backup.env.gdrive.example deploy/backup.env && nano deploy/backup.env   # atau backup.env.r2.example
```

Isi `deploy/.env`:
- `SERVER_NAME` dan `APP_URL`: domain Anda.
- `APP_KEY`: buat dengan `docker run --rm php:8.4-cli php -r "echo 'base64:'.base64_encode(random_bytes(32)), PHP_EOL;"`.
  Simpan di password manager dan **jangan diganti** setelah produksi berjalan: rahasia 2FA owner
  dienkripsi dengan kunci ini (ganti kunci = semua 2FA harus dipasang ulang).
- `POSTGRES_PASSWORD` dan `APP_DB_PASSWORD`: acak, **hanya huruf & angka** (`openssl rand -base64 24 | tr -dc A-Za-z0-9`).
- `BACKUP_HEARTBEAT_URL` (opsional).
- `SENTRY_LARAVEL_DSN`: DSN proyek Laravel di Sentry (kosong = pelacak error mati).
- `MAIL_*`: kredensial SMTP dari langkah 1.7. Uji setelah deploy: di app, **Masuk → Lupa password?**
  dengan email owner, kode harus sampai dalam 1 menit.

Isi `deploy/backup.env` sesuai pilihan penyimpanan (token Google Drive, atau kunci R2).

```bash
C="docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env"
$C up -d --build
$C exec app php artisan migrate --force
$C exec app php artisan pos:create-tenant berrybrew "BerryBrew" --owner-email=<email-owner>
```

Command terakhir menampilkan **password & PIN owner sekali saja**. Serahkan langsung ke owner.

Lalu aktifkan **2FA owner** bersama owner (HP owner di tangan, aplikasi Google Authenticator / Aegis
terpasang). Setelah aktif, mendaftarkan tablet baru butuh email + password + kode 6 digit:

```bash
$C exec -it app php artisan pos:owner-2fa <email-owner>
```

Perintah menampilkan kunci sekali (ketik di aplikasi authenticator, atau buat QR dari URI yang
ditampilkan), lalu meminta satu kode untuk konfirmasi. Jam HP owner harus otomatis.

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
2. Naikkan `version:` di `app/pubspec.yaml` (mis. `1.0.1+2`), lalu build. `API_URL` **wajib** (tanpa itu
   layar daftar/masuk menampilkan kolom alamat server untuk development); `SENTRY_DSN` opsional
   (tanpa itu pelacak error app mati):
   ```bash
   cd app && flutter build apk --release --split-per-abi --dart-define=API_URL=https://<domain-api> --dart-define=SENTRY_DSN=<dsn-flutter>
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
| Aktifkan / ganti 2FA owner | `$C exec -it app php artisan pos:owner-2fa <email>` |
| HP owner hilang (matikan 2FA) | `$C exec app php artisan pos:owner-2fa <email> --disable`, lalu reset password & aktifkan lagi |
| Log aplikasi | `$C logs -f app` |
| Log backup | `$C logs backup` |

## 8. Retensi & penghapusan data (offboarding kedai)

- **Selama berlangganan**: semua data transaksi disimpan. Backup harian disimpan **30 hari** di penyimpanan backup (Google Drive / R2).
- **Kedai berhenti berlangganan**:
  1. Ekspor dan serahkan datanya ke klien:
     `$C exec app php artisan pos:export-tenant <kode>` (JSON tanpa password/PIN/token,
     tersimpan di `storage/app/private/exports/` di dalam container). Salin keluar dengan
     `$C cp app:/app/storage/app/private/exports ./exports`.
  2. Hapus permanen: `$C exec app php artisan pos:delete-tenant <kode> --confirm=<kode>`.
     Kedai lain tidak tersentuh, dan jejak penghapusan tercatat di log server.
  3. Data masih ada di backup lama sampai masa retensi 30 hari habis, lalu hilang sepenuhnya.

## Lampiran: tunnel development (ngrok, sementara sebelum VPS)

Supaya tablet di jaringan lain bisa memakai server di laptop. Alamat tetap (akun ngrok gratis):
`https://residency-handsaw-viability.ngrok-free.dev`. Authtoken disimpan di `deploy/.env.ngrok`
(di-ignore git; isi `NGROK_AUTHTOKEN=` tanpa tanda kutip).

```bash
# nyalakan (ikut menyala lagi saat Docker start)
docker run -d --name strukasir-ngrok --restart unless-stopped --network strukasir_default   --env-file deploy/.env.ngrok ngrok/ngrok:latest http api:8000   --url=https://residency-handsaw-viability.ngrok-free.dev --log=stdout
# matikan setelah selesai mencoba (server dev jadi tidak bisa diakses dari internet)
docker rm -f strukasir-ngrok
```

APK tablet untuk tunnel ini: `flutter build apk --debug --split-per-abi --target-platform android-arm64
--dart-define=API_URL=https://residency-handsaw-viability.ngrok-free.dev`. Alamat tertanam selalu menang
atas alamat yang tersimpan di tablet, jadi tablet lama tidak perlu didaftarkan ulang.

