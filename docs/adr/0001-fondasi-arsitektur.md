# ADR 0001 — Fondasi arsitektur BerryBrew POS

- **Status:** diterima
- **Tanggal:** 2026-10-03

Keputusan yang mahal untuk diubah belakangan. Masing-masing berisi alasan dan pemicu untuk meninjau ulang.

## 1. App kasir: Flutter Android (bukan web/PWA)
Printer iware 58mm kemungkinan Bluetooth **Classic (SPP)**. Web Bluetooth di browser hanya mendukung BLE,
sedangkan Flutter bisa memakai SPP lewat `print_bluetooth_thermal`. Klien juga meminta "app".
**Tinjau ulang** bila M1 gagal di printer asli.

## 2. Backend: Laravel 12 + PostgreSQL di VPS
Fitur bawaan lengkap (Sanctum, validasi, Policies, migrasi, scheduler), dan Filament tersedia untuk super-admin.
Hosting murah. PostgreSQL dipilih untuk RLS, constraint/trigger, dan query laporan. Laravel 12 butuh **PHP 8.4**.

## 3. Multi-tenant: shared database, dua lapis isolasi
- **Lapis 1, Eloquent:** trait `BelongsToTenant` + `TenantScope`. Gagal keras (`MissingTenantContext`)
  bila tidak ada konteks tenant, dan `tenant_id` diisi dari konteks server, bukan dari request.
- **Lapis 2, PostgreSQL RLS** (`App\Support\Database\Rls`) di semua tabel bisnis, dengan `FORCE ROW LEVEL SECURITY`.
  Kebijakan membaca `app.tenant_id` yang disetel `TenantContext`. Query mentah pun ikut terfilter.
- **App terhubung sebagai role non-superuser** (`berrybrew_app`), karena superuser selalu menembus RLS.
  Ini wajib juga di produksi.
- **FK komposit `(tenant_id, x_id) → (tenant_id, id)`**: database menolak referensi lintas tenant.
- Tabel identitas (`users`, `devices`, `tenants`) **tanpa RLS**, karena dibaca saat resolusi token sebelum
  tenant diketahui. Isolasinya diuji di `TenantIsolationTest`.
- **Tinjau ulang** bila memakai Laravel Octane / koneksi persisten: variabel sesi PostgreSQL harus direset
  per request.

## 4. Kustomisasi per klien: entitlement × permission
Izin efektif = role user (`App\Enums\Role` → `Permission`) **dan** fitur aktif kedai (`FeatureGate`:
`plan_features` lalu ditimpa `tenant_features`). Dilarang menulis `if tenant == ...` di kode.

## 5. Autentikasi: token perangkat + PIN
Owner mendaftarkan tablet (email + password) dan mendapat token perangkat. Staf login PIN 4–6 digit dan
mendapat token user 16 jam yang terikat ke tablet. Mencabut tablet langsung mematikan semua sesinya.
Brute force ditahan rate limit per IP (10/menit) dan lockout per akun (5 salah → kunci 5 menit).
**Email owner unik global**: email adalah identitas login tanpa memilih kedai. Konsekuensinya, satu email
tidak bisa jadi owner di dua kedai. Tinjau ulang bila ada pemilik multi-kedai.

## 6. Offline-tolerant
ID order dan pembayaran berupa UUID yang dibuat tablet dan sekaligus menjadi idempotency key. Struk dicetak
dari data lokal, tidak menunggu server. Antrean offline penuh (cash) ditunda ke v1.1.

## 7. Aturan uang ditegakkan database
- Nominal integer rupiah, dengan `currency` disimpan eksplisit.
- `payments` & `audit_logs` **append-only** (trigger). Refund = baris baru `kind=refund`.
- Status order hanya maju (`open→paid→void`, `open→void`). Total order final dibekukan.
  Void wajib berisi alasan dan pelaku.
- Satu shift terbuka per tablet (partial unique index).
- Pengecualian purge hanya untuk offboarding tenant (`app.allow_purge = on`).

## Entitas (ringkas)
`plans`, `features`, `plan_features`, `tenants`, `tenant_features`, `tenant_settings`, `users`, `devices`,
`audit_logs` · menu: `categories`, `products`, `modifier_groups`, `modifiers`, `product_modifier_groups` ·
transaksi: `shifts`, `order_counters`, `orders`, `order_items`, `order_item_modifiers`, `payments`.
Sumber kebenaran: `backend/database/migrations/`.
