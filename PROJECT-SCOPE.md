# Project Scope & Competency Ledger

- **Category:** internal-tools +payments +multi-tenant
- **Security tags:** always, deploy, auth, admin, money, upload
  (`upload` ditambahkan 2026-10-06: owner mengunggah logo struk.)
  (`webhook` dari +payments di-drop untuk v1: belum ada payment gateway — QRIS statis dikonfirmasi manual.
  Reopen saat QRIS dinamis / gateway apa pun ditambahkan.)
- **Classified:** 2026-10-03
- **Last audit:** 2026-10-09
- **Gates open:** 6 kompetensi blocking (#5, 6, 27, 44, 46, 48); semua security check blocking PASS/n/a
  — hampir semuanya menunggu server produksi & akun (lihat docs/deploy.md); #6 menunggu keputusan owner
- **Checkpoint terakhir:** skema `customers` (data pribadi: nama, no HP, tgl lahir, catatan) + `orders.customer_id`, endpoint `/customers` kasir/owner, import CSV, anonimisasi UU PDP (`CustomerTest`) — 2026-10-09. Sebelumnya `GET/PUT /settings/features` (owner, `settings.manage`): override fitur per kedai dalam batas paket, aturan ketergantungan, audit (`FeatureSettingsTest`) — 2026-10-07. Sebelumnya endpoint publik `POST /signup` (pendaftaran mandiri) + kolom profil usaha di `tenants` — 2026-10-07. M6 deploy (paket produksi diuji lokal: HTTPS, alur kasir, backup + restore) — 2026-10-03. M1 printer: menunggu printer tersedia di lokasi.

Konteks: STRUKASIR, POS Android (Flutter) + Laravel 12 API + PostgreSQL; klien pertama kedai kopi BerryBrew, dengan fondasi
multi-tenant agar bisa dijual sebagai subscription. Plan lengkap: lihat `docs/` (menyusul) dan catatan plan.

## Blocking (must be `applied` before launch)
| # | Competency | Status | Evidence / reason |
|---|---|---|---|
| 2 | Documentation & Maintenance | applied | `README.md` (setup dev), `docs/deploy.md` (deploy, update, rollback, rilis APK, administrasi), `docs/runbook-owner.md` (operasional harian & masalah umum), `docs/adr/0001-fondasi-arsitektur.md` |
| 5 | Cost & FinOps | deferred | Rencana: VPS lokal harga tetap ±Rp50–150rb/bln (1–2 vCPU, 2 GB) + domain .my.id ±Rp25rb/thn + backup Google Drive/R2 (gratis). Biaya masuk harga ke klien. Jadi `applied` setelah VPS & harga final dicatat |
| 6 | Legal & Compliance | deferred | Wajib: struk sebagai bukti transaksi, kebijakan refund owner tertulis, perlakuan pajak (PB1/service) diputuskan owner |
| 16 | Data Modeling | applied | `tenant_id` NOT NULL + index + bagian unique di semua tabel bisnis; FK komposit `(tenant_id, id)`; constraint & CHECK di DB (`backend/database/migrations/`); entitas di `docs/adr/0001-fondasi-arsitektur.md` |
| 18 | Data Validation | applied | FormRequest / `validate()` di semua endpoint tulis; constraint, CHECK, FK komposit & trigger di DB; nominal & qty dibatasi |
| 19 | Data Lifecycle | applied | Audit before/after untuk login, menu/harga, diskon disetujui, bayar, void+refund, shift; `payments` & `audit_logs` append-only (trigger); modifier dinonaktifkan bukan dihapus; ekspor & hapus per kedai `pos:export-tenant` / `pos:delete-tenant` (`TenantDataTest`); retensi di `docs/deploy.md` §8 Pelanggan: hapus data atas permintaan = anonimisasi (`CustomerService::anonymize`: nama/HP/tgl lahir/catatan + label nama di order dikosongkan, angka penjualan tetap), audit pelanggan tanpa isi data pribadi, `customers` ikut ekspor/hapus tenant (`CustomerTest`). |
| 20 | Idempotency & Concurrency | applied | UUID dari tablet sebagai idempotency key untuk order, pembayaran, void (idempoten), registrasi tablet (`device_id`); `lockForUpdate` di bayar/void/tutup shift/nomor order; diuji di `OrderTest`, `AuthTest`, `ShiftVoidReportTest` |
| 24 | Multi-tenancy & Data Isolation | applied | `BelongsToTenant` fail-closed + RLS FORCE + role DB non-superuser + FK komposit; test lintas tenant `TenantIsolationTest`, `MenuTest::test_cannot_touch_another_tenants_menu`; berjalan di CI (`.github/workflows/ci.yml`, role non-superuser) — run 37121641161 hijau |
| 25 | Authentication & Authorization | applied | Token perangkat + PIN (Sanctum, hash bcrypt), token user 16 jam terikat tablet, lockout, cabut tablet = cabut sesi, reset owner via `pos:reset-owner-password` (cabut semua sesi); pendaftaran mandiri `POST /signup` membuat usaha + owner + tablet pertama (`SignupController`, `SignupTest`); email calon owner diverifikasi dengan kode 6 digit SEBELUM usaha dibuat (`SignupCodes`, `POST /signup/email-code`, `SignupTest`); lupa password dengan kode 6 digit (`EmailCodes`, `EmailCodeTest`); `AuthTest`, `AdminCommandsTest`. Belum: akun SMTP produksi |
| 26 | Permissions & Access Control | applied | Izin = `Role`→`Permission` ∩ `FeatureGate`, dicek server: route `can:` (menu, order, shift, laporan), persetujuan PIN owner untuk diskon > batas & void (`Approval`); `MenuTest`, `OrderTest`, `ShiftVoidReportTest` |
| 27 | Security & SSL | deferred | Siap & teruji lokal: Caddy HTTPS + redirect 308 + HSTS + header keamanan + tanpa header Server/X-Powered-By, `APP_DEBUG=false`. Jadi `applied` setelah dicek di domain produksi |
| 29 | Environment Variables & Secrets | applied | `backend/.env.example`, `deploy/.env.example`; `.env`, `deploy/.env`, keystore & `key.properties` di-gitignore; riwayat git dipindai bersih (SEC-24); rahasia produksi hanya di `deploy/.env` server |
| 32 | Payments & Billing | applied | Tanpa gateway (QRIS statis). State machine `open→paid→void` ditegakkan trigger DB; refund = baris `kind=refund` append-only (`OrderService::void`); rekonsiliasi: tutup shift (kas seharusnya vs dihitung, `ShiftService`) + laporan per metode untuk dicocokkan dengan mutasi QRIS/EDC (`ReportService`); diuji `OrderTest`, `ShiftVoidReportTest` |
| 43 | Automated Testing | applied | 85 test backend (isolasi, auth, menu, order, bayar, shift, void, laporan, command) + 27 test Flutter (harga = fixture server, struk, modifier, versi) — semua di CI. Uji UI di perangkat asli: lihat Preflight |
| 44 | Logging & Monitoring | deferred | Log JSON ke stderr (`LOG_CHANNEL=stderr`), heartbeat backup (`BACKUP_HEARTBEAT_URL`). Belum: UptimeRobot `/up` + healthchecks.io dipasang (`docs/deploy.md` §1) |
| 46 | Error Handling | deferred | Tidak ada jalur "uang diterima tapi tidak tercatat": bayar atomik di server, kiriman ulang aman, 409 dicek ulang di app, gagal cetak tidak membatalkan transaksi. Pelacak error Sentry siap di server (`Integration::handles`, tag tenant_id/device_code) dan app (`SentryFlutter.init` via `--dart-define=SENTRY_DSN`); privasi dikunci: tanpa PII, tanpa isi request, tanpa screenshot (`config/sentry.php`, `SentryConfigTest`). Belum: akun Sentry & DSN diisi di produksi |
| 48 | Backup & Recovery | deferred | `deploy/backup/` pg_dump harian (superuser, menembus RLS) → rclone (Google Drive atau R2, `deploy/backup.env`), retensi 30 hari; **uji restore lokal lolos** (jumlah baris identik, 14 policy RLS + trigger ikut, guard timpa produksi). Belum: uji restore di produksi; restore satu tenant (prosedur manual) |

## Recommended
| # | Competency | Status | Evidence / reason |
|---|---|---|---|
| 1 | Requirements & Scoping | applied | Lingkup v1 & ditunda tertulis di plan (`C:\Users\User\.claude\plans\aku-dapat-project-diminta-calm-hennessy.md`); akan disalin ke `docs/scope.md` |
| 3 | Architecture Decision Records | applied | `docs/adr/0001-fondasi-arsitektur.md` |
| 4 | Client & Stakeholder Management | deferred | Skema harga (subs / beli putus) belum diputuskan klien; buat change-request log saat kontrak disepakati |
| 7 | Frontend | deferred | State loading/empty/error di tiap layar Flutter |
| 8 | UI/UX & Responsiveness | deferred | HP & tablet, portrait/landscape (compact/medium/expanded + layar pendek). Progres: `app/test/responsive_test.dart` merender 16 layar × 12 ukuran (320×568 s.d. 1366×1024) × skala font 1.0/1.3 dan gagal bila overflow; skala font dibatasi 1.2× (`appBuilder`). Belum: dicek di TablePC asli |
| 9 | Application State | deferred | Riverpod; server = sumber kebenaran, drift hanya cache + antrean |
| 12 | i18n / Timezone / Locale / Currency | deferred | Timestamp UTC di DB, tampil Asia/Jakarta; format Rupiah id_ID; nomor order per hari lokal |
| 14 | APIs & Backend Logic | deferred | Kontrak respons/error konsisten, didokumentasikan di `docs/api.md` |
| 15 | Database & Storage | deferred | Index di semua FK dan kolom filter (tenant_id, created_at, status) |
| 17 | Database Migration & Schema Evolution | applied | Migrasi versioned di `backend/database/migrations/`, ter-commit (b0293c0) |
| 21 | Search | deferred | Cari produk/riwayat via index biasa; volume kecil |
| 28 | Rate Limiting | deferred | Throttle global + ketat di login PIN/password (lihat SEC-12) |
| 30 | Dependency & Supply Chain | applied | `composer.lock` & `pubspec.lock` ter-commit; `composer audit` di CI; `.github/dependabot.yml` (composer, pub, actions) |
| 35 | Hosting & Deployment | applied | Deploy reproducible: `deploy/docker-compose.prod.yml` + `deploy/Dockerfile` (di-build di CI); langkah deploy, update & rollback di `docs/deploy.md`; diuji lokal end-to-end |
| 36 | Cloud & Infrastructure | deferred | VPS penyedia lokal, lokasi Jakarta (latensi & data di Indonesia); pilihan final dicatat di `docs/deploy.md` saat dibeli |
| 37 | CI/CD & Version Control | deferred | Progres: CI menjalankan Pint, audit, test backend, flutter analyze/test. Belum: proteksi branch `main`, deploy dari pipeline |
| 40 | Feature Flags & Progressive Rollout | applied | `plan_features` + `tenant_features` + `App\Support\Tenancy\FeatureGate`; `AuthTest::test_disabling_a_feature_removes_dependent_permissions` |
| 41 | Local Dev Reproducibility | applied | `docker-compose.yml` (opcache dev) + seeder + `.env.example`; langkah di `README.md` |
| 42 | Code Quality Automation | applied | `pint --test` + `flutter analyze` di CI |
| 45 | Tracing & Correlation ID | deferred | Request ID di log API; order UUID sebagai korelasi tablet↔server |
| 47 | Availability & Incident Handling | deferred | Langkah darurat untuk kasir (server down → app tetap print; hotspot HP) di runbook |
| 49 | Bus Factor & Continuity | deferred | Daftar yang wajib disimpan di password manager bersama ada di `docs/deploy.md` (Oracle, domain, Cloudflare/R2, keystore APK + password). Belum dilakukan |
| 50 | Admin / Back-office Tooling | deferred | Owner mengelola menu/user/laporan di app; koreksi data tanpa DB client |
| 22 | File & Media Handling | applied | Logo struk per kedai: diproses di tablet (hitam-putih, ≤ 384 px, `receipt_logo.dart`), disimpan sebagai base64 di `tenant_settings.receipt_logo` (CHECK ≤ 87.400 karakter), divalidasi server (`App\Support\ReceiptLogo`), dikirim ke tablet lewat `GET /menu`; diuji `ReceiptSettingsTest`, `receipt_logo_test.dart`. Foto produk masih ditunda |

## Deferred by decision
| # | Competency | Reason | Reopen when |
|---|---|---|---|
| 10 | Accessibility | Dipakai staf terlatih di satu perangkat; tetap target sentuh besar & kontras cukup | Ada klien/regulasi yang mensyaratkan |
| 13 | Performance & Optimization | Volume kecil; dijaga lewat UI ringan | Layar terasa lambat di tablet TablePC atau laporan > 2 detik |
| 23 | Queues & Asynchronous Processing | Tidak ada pekerjaan > 2 detik di v1 | Export Excel, laporan berat, atau integrasi eksternal (GoFood, gateway) |
| 38 | Cache & CDN | API privat untuk app native, tanpa aset web | Ada web dashboard |
| 39 | Scalability | Satu kedai, ratusan transaksi/hari | Tenant ke-5 atau > 5.000 order/hari total |
| 51 | Product Analytics & Event Tracking | Owner melihat laporan penjualan; analitik pemakaian belum perlu | Mulai dijual ke banyak kedai (butuh tahu fitur mana yang dipakai) |

## Not applicable
| # | Competency | Why |
|---|---|---|
| 11 | SEO & Metadata | Aplikasi internal, tidak ada halaman publik |
| 31 | Webhooks & Third-Party Integrations | Tidak ada inbound webhook/gateway di v1 (QRIS statis). Reopen saat QRIS dinamis/GoFood |
| 33 | Transactional Email & Deliverability | Tidak mengirim email di v1 |
| 34 | AI / LLM Integration | Tidak ada fitur AI |

## Security checks
| ID | Check | Severity | → # | Status | Evidence / reason |
|---|---|---|---|---|---|
| SEC-01 | Injection | critical | 27 | PASS | Query lewat Eloquent/query builder; raw SQL hanya `set_config` berparameter (`TenantContext`) dan DDL migrasi dengan nama tabel konstan (`Rls`); `selectRaw` statis di `MenuController`. Dinilai ulang tiap endpoint baru: `/signup` mengisi profil usaha eksplisit (di luar `$fillable`), `status`/`plan_id`/`code`/`role` dari input diabaikan (`SignupTest::test_tenant_cannot_be_hijacked_via_mass_assignment`) |
| SEC-02 | XSS | critical | 27 | n/a | Klien = app Flutter native, API hanya JSON, tidak ada render HTML. Reopen jika ada web dashboard |
| SEC-03 | Mass assignment | critical | 18 | PASS | FormRequest di semua endpoint (`app/Http/Requests`); `$fillable` eksplisit tanpa `tenant_id`/`role`/`failed_attempts`; `tenant_id` ditimpa dari konteks (`TenantIsolationTest::test_tenant_id_is_taken_from_context_not_from_input`). Dinilai ulang tiap endpoint baru: `/signup` mengisi profil usaha eksplisit (di luar `$fillable`), `status`/`plan_id`/`code`/`role` dari input diabaikan (`SignupTest::test_tenant_cannot_be_hijacked_via_mass_assignment`) `/customers`: `code`, `tenant_id`, `anonymized_at` dari input diabaikan (`CustomerTest::test_code_and_tenant_cannot_be_set_from_request`). |
| SEC-04 | Path traversal | critical | 22 | PASS | Tidak ada file di disk: logo disimpan di kolom DB, tidak ada path dari input pengguna |
| SEC-08 | Insecure deserialization | high | 18 | PASS | Hanya JSON tervalidasi; tidak ada `unserialize`/`eval` (dipindai) |
| SEC-09 | Open redirect | medium | 27 | n/a | API tanpa redirect (bearer token, tanpa callback URL) |
| SEC-10 | Password policy | high | 25 | PASS | Owner membuat password saat `/signup`: min. 8 karakter, huruf + angka (`SignupRequest`, `Password::min(8)->letters()->numbers()`), tanpa cek kebocoran (butuh internet keluar). PIN owner 6 digit, tolak angka sama/berurutan; PIN lain 4–6 digit + lockout. Password via command tetap 16 karakter acak |
| SEC-11 | Password hashing | critical | 25 | PASS | bcrypt: cast `hashed` untuk password, `Hash::make` untuk PIN (`User::setPin`) |
| SEC-12 | Rate limiting & brute-force | high | 28 | PASS | Limiter `api` 120/menit per token/IP, `auth` 10/menit per IP (`AppServiceProvider`); lockout per akun 5× salah → 5 menit (`User::registerFailedAttempt`, `AuthTest`); `signup` 10/menit + 5 pendaftaran berhasil/jam per IP (`SignupTest`). Email terdaftar terungkap di `/signup` (kompromi umum UX daftar; dibatasi throttle). Belum: captcha bila ada penyalahgunaan |
| SEC-13 | Session cookies | critical | 25 | n/a | Tidak memakai cookie; Sanctum personal access token via header, disimpan di flutter_secure_storage |
| SEC-14 | CSRF | high | 27 | n/a | Bearer header murni tanpa cookie auth |
| SEC-15 | JWT handling | critical | 25 | n/a | Sanctum token opaque (hash di DB), bukan JWT |
| SEC-16 | Session lifecycle | high | 25 | PASS | Logout hapus token; token user kedaluwarsa 16 jam; 1 sesi per user per tablet; cabut tablet / reset owner mencabut semua sesi (`AuthTest`, `AdminCommandsTest`). Belum ada fitur ganti PIN mandiri |
| SEC-17 | Password reset flow | critical | 25 | PASS | Reset owner via kode 6 digit ke email (`PasswordResetController`, `EmailCodes`): hanya hash disimpan, berlaku 15 menit, sekali pakai, maks. 5 salah, kode baru membatalkan kode lama, jeda kirim 60 detik, throttle `auth`; respons "minta kode" sama untuk email terdaftar/tidak; kode reset ≠ kode verifikasi; reset tidak melewati 2FA pendaftaran tablet; tercatat di audit log (`EmailCodeTest`). Reset via artisan tetap ada |
| SEC-19 | MFA & re-authentication | medium | 25 | PASS | Aksi destruktif (void, refund, diskon > limit) wajib PIN owner ulang (`Approval`). 2FA TOTP owner untuk pendaftaran tablet (satu-satunya login password): rahasia terenkripsi (`encrypted` cast), anti-replay per langkah waktu, kode salah ikut lockout & audit (`App\Support\TwoFactor`, `DeviceRegistrationController`, `pos:owner-2fa`); diuji `TwoFactorTest` |
| SEC-20 | Broken access control / IDOR | critical | 26 | PASS | Semua route `{id}` (categories, products, modifier-groups) di-resolve setelah tenant ditetapkan → ID kedai lain 404; referensi lintas tenant ditolak (`MenuTest::test_cannot_touch_another_tenants_menu`, `TenantIsolationTest`). Dinilai ulang tiap endpoint baru: `/signup` mengisi profil usaha eksplisit (di luar `$fillable`), `status`/`plan_id`/`code`/`role` dari input diabaikan (`SignupTest::test_tenant_cannot_be_hijacked_via_mass_assignment`) `/customers/{id}` kedai lain 404; `customer_id` kedai lain di order ditolak (FK komposit + 422); kasir tidak bisa lihat detail/ubah/hapus/import; no HP kasir tersamar (`CustomerTest`). |
| SEC-21 | Business logic flaws | critical | 14 | PASS | `PricingService` menghitung ulang dari harga server; klien hanya kirim produk/qty/modifier; qty 1–999, diskon dibatasi, total bayar harus pas (`OrderTest`) |
| SEC-22 | Race conditions | critical | 20 | PASS | Bayar: `lockForUpdate` + cek status di transaksi; nomor order dari `order_counters` terkunci; PK UUID order/pembayaran dari tablet = idempotency key (`OrderTest::test_resending_*`, `test_paying_twice_*`) Kode member dari `UPDATE tenant_settings … RETURNING customer_seq` (atomik); no HP unik per kedai via unique index parsial, bentrok paralel → 422. |
| SEC-23 | Webhook verification | critical | 31 | n/a | Tag `webhook` di-drop: tidak ada gateway di v1. Reopen saat QRIS dinamis |
| SEC-24 | Secrets management | critical | 29 | PASS | Riwayat git dipindai: tidak ada APP_KEY, password seed, kunci R2 atau private key; file rahasia di-gitignore |
| SEC-25 | Verbose errors | high | 46 | PASS | `APP_DEBUG=false` di compose produksi; 404/500 JSON generik tanpa trace (diverifikasi di build produksi lokal); `MissingTenantContext` → 500 generik |
| SEC-27 | Unsafe file uploads | critical | 22 | PASS | Logo: hanya PNG dicek dari magic bytes + `getimagesizefromstring`, maks. 64 KB & 384×400 px, SVG/JPEG/PNG palsu ditolak (`ReceiptLogo::validate`, `ReceiptSettingsTest::test_only_small_png_is_accepted`); tidak pernah disajikan sebagai file dari origin app (hanya base64 di JSON ber-token); hanya izin `settings.manage` (owner) |
| SEC-28 | Storage bucket access | critical | 22 | n/a | Tidak ada bucket/object storage: logo di database (ikut RLS & backup) |
| SEC-26 | Unbounded data fetching | high | 14 | PASS | `GET /orders` & `/shifts` paginasi maks 50; laporan dibatasi 1 tahun; menu & staf terbatas ukuran kedai; resource tanpa `pin_hash`/`password` `GET /customers` paginasi maks 50, import maks 2.000 baris / 512 KB. |
| SEC-29 | Source maps in production | medium | 35 | n/a | Tidak ada bundle browser |
| SEC-30 | HTTPS enforced | critical | 27 | PASS | Caddy: redirect 308 HTTP→HTTPS + HSTS 1 tahun (diverifikasi lokal; cek ulang di domain saat Preflight) |
| SEC-31 | Security headers & clickjacking | high | 27 | PASS | `SecurityHeaders` (nosniff, DENY, CSP frame-ancestors none, no-referrer, no-store) + HSTS dari Caddy; header Server dihapus |
| SEC-32 | CORS | high | 27 | PASS | `backend/config/cors.php` `allowed_origins => []` (klien native) |
| SEC-33 | Web cache poisoning | medium | 38 | PASS | Semua respons `Cache-Control: private, no-store` (`SecurityHeaders`) |
| SEC-34 | Dependencies | high | 30 | PASS | `composer audit` bersih & dijalankan di CI; lockfile ter-commit; Dependabot aktif (`.github/dependabot.yml`) |
| SEC-35 | Audit logging | medium | 19 | PASS | Login/login gagal/logout, PIN penyetuju salah, registrasi tablet, ubah menu/harga, diskon disetujui, order dibayar (metode), void/refund (alasan, penyetuju), buka/tutup shift — dengan actor, tablet, IP, tanpa PIN/token (`AppSupportAudit`). Belum ada endpoint ubah role |
| SEC-36 | Shadow & zombie endpoints | medium | 14 | PASS | Hanya `/api/v1/*` + `/up`; halaman welcome Laravel dihapus (`GET /` → 404) |
| SEC-38 | Denial of wallet | high | 5 | PASS | VPS harga tetap bulanan (tanpa tagihan per pemakaian); tidak ada endpoint mahal (AI/upload/email); rate limit aktif; backup ±100 KB/hari jauh di bawah kuota gratis |
| SEC-39 | Subdomain takeover | medium | 36 | FAIL | Audit DNS saat domain dipasang |
