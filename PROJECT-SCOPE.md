# Project Scope & Competency Ledger

- **Category:** internal-tools +payments +multi-tenant
- **Security tags:** always, deploy, auth, admin, money
  (`webhook` dari +payments di-drop untuk v1: belum ada payment gateway — QRIS statis dikonfirmasi manual.
  Reopen saat QRIS dinamis / gateway apa pun ditambahkan.)
- **Classified:** 2026-10-03
- **Last audit:** 2026-10-03
- **Gates open:** 16 kompetensi blocking + 16 security check blocking
  (14 critical/high berstatus FAIL + SEC-19 & SEC-35 yang medium tapi menyentuh money/admin)
- **Checkpoint terakhir:** skema (M2) — 2026-10-03. M1 printer: menunggu printer tersedia di lokasi.

Konteks: POS Android (Flutter) + Laravel 12 API + PostgreSQL untuk kedai kopi BerryBrew, dengan fondasi
multi-tenant agar bisa dijual sebagai subscription. Plan lengkap: lihat `docs/` (menyusul) dan catatan plan.

## Blocking (must be `applied` before launch)
| # | Competency | Status | Evidence / reason |
|---|---|---|---|
| 2 | Documentation & Maintenance | deferred | Belum ada kode. Wajib: README setup/deploy + runbook owner (void, tutup shift, ganti printer) sebelum handover |
| 5 | Cost & FinOps | deferred | Rencana: Oracle Always Free (PAYG) + R2 free + domain .my.id. Wajib: estimasi biaya per tenant + budget alert Oracle sebelum go-live |
| 6 | Legal & Compliance | deferred | Wajib: struk sebagai bukti transaksi, kebijakan refund owner tertulis, perlakuan pajak (PB1/service) diputuskan owner |
| 16 | Data Modeling | applied | `tenant_id` NOT NULL + index + bagian unique di semua tabel bisnis; FK komposit `(tenant_id, id)`; constraint & CHECK di DB (`backend/database/migrations/`); entitas di `docs/adr/0001-fondasi-arsitektur.md` |
| 18 | Data Validation | deferred | Laravel FormRequest per endpoint + constraint DB |
| 19 | Data Lifecycle | deferred | Progres: `audit_logs` append-only (trigger) + `App\Support\Audit` mencatat login, login gagal, logout, registrasi tablet; `payments` append-only. Belum: audit void/refund/diskon/ubah harga (M4–M5), ekspor & hapus per tenant |
| 20 | Idempotency & Concurrency | deferred | Progres: PK `orders.id`/`payments.id` = UUID dari tablet; partial unique 1 shift terbuka/tablet; `lockForUpdate` saat registrasi tablet. Belum: endpoint order/bayar idempotent (M4) |
| 24 | Multi-tenancy & Data Isolation | deferred | Struktural selesai: `BelongsToTenant` fail-closed + RLS FORCE + role DB non-superuser + FK komposit; `tests/Feature/TenantIsolationTest.php` (10 test). Belum `applied` karena syarat "test berjalan di CI" belum ada (#37) |
| 25 | Authentication & Authorization | deferred | Progres: token perangkat + PIN (`AuthController`, `DeviceRegistrationController`), token user 16 jam terikat tablet, lockout. Belum: kebijakan password owner (SEC-10), cabut sesi saat ganti PIN (SEC-16) |
| 26 | Permissions & Access Control | deferred | Progres: `Role`→`Permission` + `FeatureGate` sebagai Gate di `AppServiceProvider`, diuji di `AuthTest`. Belum ada endpoint mutasi yang memakainya (M3+) |
| 27 | Security & SSL | deferred | HTTPS + HSTS di server produksi; tanpa SQL string concatenation |
| 29 | Environment Variables & Secrets | deferred | `.env.example`, `.env` di-gitignore; secret produksi hanya di server |
| 32 | Payments & Billing | deferred | Tanpa gateway di v1. Bar yang berlaku: state machine order open→paid→void (terminal jelas), refund path, payments append-only, rekonsiliasi kas per shift + rekap QRIS harian vs mutasi merchant |
| 43 | Automated Testing | deferred | Pest: isolasi tenant, idempotensi, pricing fixture bersama, permission void; Flutter unit test PricingEngine |
| 44 | Logging & Monitoring | deferred | Log terstruktur + uptime check dengan alert (mis. UptimeRobot free) sebelum go-live |
| 46 | Error Handling | deferred | Tidak boleh ada jalur "uang diterima tapi order tidak tercatat": order disimpan lokal dulu, sinkron dengan retry, status sinkron terlihat |
| 48 | Backup & Recovery | deferred | pg_dump harian → Cloudflare R2; uji restore penuh + restore satu tenant sebelum go-live |

## Recommended
| # | Competency | Status | Evidence / reason |
|---|---|---|---|
| 1 | Requirements & Scoping | applied | Lingkup v1 & ditunda tertulis di plan (`C:\Users\User\.claude\plans\aku-dapat-project-diminta-calm-hennessy.md`); akan disalin ke `docs/scope.md` |
| 3 | Architecture Decision Records | applied | `docs/adr/0001-fondasi-arsitektur.md` |
| 4 | Client & Stakeholder Management | deferred | Skema harga (subs / beli putus) belum diputuskan klien; buat change-request log saat kontrak disepakati |
| 7 | Frontend | deferred | State loading/empty/error di tiap layar Flutter |
| 8 | UI/UX & Responsiveness | deferred | Target: tablet TablePC landscape; cepat disentuh, ringan untuk CPU lemah. Diverifikasi di perangkat asli, bukan 360/768/1280px |
| 9 | Application State | deferred | Riverpod; server = sumber kebenaran, drift hanya cache + antrean |
| 12 | i18n / Timezone / Locale / Currency | deferred | Timestamp UTC di DB, tampil Asia/Jakarta; format Rupiah id_ID; nomor order per hari lokal |
| 14 | APIs & Backend Logic | deferred | Kontrak respons/error konsisten, didokumentasikan di `docs/api.md` |
| 15 | Database & Storage | deferred | Index di semua FK dan kolom filter (tenant_id, created_at, status) |
| 17 | Database Migration & Schema Evolution | deferred | File migrasi versioned ada di `backend/database/migrations/`; jadi `applied` setelah di-commit ke git |
| 21 | Search | deferred | Cari produk/riwayat via index biasa; volume kecil |
| 28 | Rate Limiting | deferred | Throttle global + ketat di login PIN/password (lihat SEC-12) |
| 30 | Dependency & Supply Chain | deferred | composer.lock & pubspec.lock di-commit; `composer audit`; Dependabot saat repo di GitHub |
| 35 | Hosting & Deployment | deferred | Deploy reproducible ke Oracle VM + prosedur rollback tertulis |
| 36 | Cloud & Infrastructure | deferred | Region Oracle dipilih sengaja (Singapore/Jakarta), didokumentasikan |
| 37 | CI/CD & Version Control | deferred | GitHub Actions: lint + test backend & Flutter sebelum deploy |
| 40 | Feature Flags & Progressive Rollout | applied | `plan_features` + `tenant_features` + `App\Support\Tenancy\FeatureGate`; `AuthTest::test_disabling_a_feature_removes_dependent_permissions` |
| 41 | Local Dev Reproducibility | applied | `docker-compose.yml` + `docker/` + seeder + `.env.example`; langkah di `README.md` |
| 42 | Code Quality Automation | deferred | Laravel Pint + `flutter analyze` di CI |
| 45 | Tracing & Correlation ID | deferred | Request ID di log API; order UUID sebagai korelasi tablet↔server |
| 47 | Availability & Incident Handling | deferred | Langkah darurat untuk kasir (server down → app tetap print; hotspot HP) di runbook |
| 49 | Bus Factor & Continuity | deferred | Kredensial Oracle, R2, domain, keystore APK dicatat di password manager yang bisa diakses pihak kedua |
| 50 | Admin / Back-office Tooling | deferred | Owner mengelola menu/user/laporan di app; koreksi data tanpa DB client |

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
| 22 | File & Media Handling | v1 tanpa upload (foto produk opsional ditunda). Reopen jika foto produk/logo diunggah |
| 31 | Webhooks & Third-Party Integrations | Tidak ada inbound webhook/gateway di v1 (QRIS statis). Reopen saat QRIS dinamis/GoFood |
| 33 | Transactional Email & Deliverability | Tidak mengirim email di v1 |
| 34 | AI / LLM Integration | Tidak ada fitur AI |

## Security checks
| ID | Check | Severity | → # | Status | Evidence / reason |
|---|---|---|---|---|---|
| SEC-01 | Injection | critical | 27 | FAIL | Belum ada kode. Eloquent/query builder saja, tanpa raw SQL berisi input |
| SEC-02 | XSS | critical | 27 | n/a | Klien = app Flutter native, API hanya JSON, tidak ada render HTML. Reopen jika ada web dashboard |
| SEC-03 | Mass assignment | critical | 18 | PASS | FormRequest di semua endpoint (`app/Http/Requests`); `$fillable` eksplisit tanpa `tenant_id`/`role`/`failed_attempts`; `tenant_id` ditimpa dari konteks (`TenantIsolationTest::test_tenant_id_is_taken_from_context_not_from_input`). Dinilai ulang tiap endpoint baru |
| SEC-08 | Insecure deserialization | high | 18 | FAIL | Hanya JSON tervalidasi; tanpa `unserialize` input |
| SEC-09 | Open redirect | medium | 27 | n/a | API tanpa redirect (bearer token, tanpa callback URL) |
| SEC-10 | Password policy | high | 25 | FAIL | Password owner min 12 server-side; PIN kasir 6 digit + lockout (SEC-12) |
| SEC-11 | Password hashing | critical | 25 | PASS | bcrypt: cast `hashed` untuk password, `Hash::make` untuk PIN (`User::setPin`) |
| SEC-12 | Rate limiting & brute-force | high | 28 | PASS | Limiter `api` 120/menit per token/IP, `auth` 10/menit per IP (`AppServiceProvider`); lockout per akun 5× salah → 5 menit (`User::registerFailedAttempt`, `AuthTest`) |
| SEC-13 | Session cookies | critical | 25 | n/a | Tidak memakai cookie; Sanctum personal access token via header, disimpan di flutter_secure_storage |
| SEC-14 | CSRF | high | 27 | n/a | Bearer header murni tanpa cookie auth |
| SEC-15 | JWT handling | critical | 25 | n/a | Sanctum token opaque (hash di DB), bukan JWT |
| SEC-16 | Session lifecycle | high | 25 | FAIL | Progres: logout menghapus token, token user kedaluwarsa 16 jam, 1 sesi per user per tablet, cabut tablet = cabut sesi (`AuthTest`). Belum: ganti PIN/password mencabut token lain |
| SEC-17 | Password reset flow | critical | 25 | n/a | Tidak ada reset mandiri di v1 (tanpa email); reset owner via artisan command oleh developer, tercatat di audit log. Reopen jika ada reset via email/WA |
| SEC-19 | MFA & re-authentication | medium | 25 | FAIL | Aksi destruktif (void, refund, diskon > limit, ubah harga) wajib PIN owner ulang. MFA owner: deferred |
| SEC-20 | Broken access control / IDOR | critical | 26 | FAIL | Dinilai lintas tenant: semua query by ID di-scope tenant; test ganti-ID lintas tenant |
| SEC-21 | Business logic flaws | critical | 14 | FAIL | PricingService menghitung ulang di server dari harga server; tolak qty/nominal negatif/nol |
| SEC-22 | Race conditions | critical | 20 | FAIL | Progres: unique & partial unique index, UUID dari tablet, lock saat registrasi tablet. Belum: transaksi + lock pada bayar/void & penomoran order (M4) |
| SEC-23 | Webhook verification | critical | 31 | n/a | Tag `webhook` di-drop: tidak ada gateway di v1. Reopen saat QRIS dinamis |
| SEC-24 | Secrets management | critical | 29 | FAIL | `.env` di-gitignore; keystore APK & kredensial R2 tidak masuk repo |
| SEC-25 | Verbose errors | high | 46 | FAIL | `APP_DEBUG=false` di produksi; error JSON generik |
| SEC-26 | Unbounded data fetching | high | 14 | FAIL | Paginasi wajib + limit maks di endpoint list; API Resource tanpa `pin_hash`/`password` |
| SEC-29 | Source maps in production | medium | 35 | n/a | Tidak ada bundle browser |
| SEC-30 | HTTPS enforced | critical | 27 | FAIL | Caddy/Nginx + Let's Encrypt, redirect HTTP→HTTPS, HSTS |
| SEC-31 | Security headers & clickjacking | high | 27 | FAIL | Progres: `SecurityHeaders` global (nosniff, DENY, CSP, no-referrer), termasuk respons 401. Belum: HSTS di reverse proxy produksi |
| SEC-32 | CORS | high | 27 | PASS | `backend/config/cors.php` `allowed_origins => []` (klien native) |
| SEC-33 | Web cache poisoning | medium | 38 | PASS | Semua respons `Cache-Control: private, no-store` (`SecurityHeaders`) |
| SEC-34 | Dependencies | high | 30 | FAIL | `composer audit` bersih (2026-10-03). Belum: lockfile di-commit, Dependabot |
| SEC-35 | Audit logging | medium | 19 | FAIL | Progres: login, login gagal, logout, registrasi tablet tercatat dengan actor/IP, tanpa PIN (`AuthTest`). Belum: void, refund, ubah role, konfirmasi QRIS, ubah harga |
| SEC-36 | Shadow & zombie endpoints | medium | 14 | FAIL | Inventaris route (`php artisan route:list`) sesuai rencana; tanpa route debug di produksi |
| SEC-38 | Denial of wallet | high | 5 | FAIL | Budget alert Oracle (akun PAYG) + tetap di kuota Always Free |
| SEC-39 | Subdomain takeover | medium | 36 | FAIL | Audit DNS saat domain dipasang |
