# BerryBrew POS

Sistem kasir (POS) untuk kedai kopi BerryBrew: app Android (Flutter) + API Laravel 12 + PostgreSQL,
dengan fondasi multi-tenant agar bisa dipakai kedai lain.

| Folder | Isi |
|---|---|
| `backend/` | Laravel 12 API (Sanctum, PostgreSQL + Row-Level Security) |
| `app/` | App Flutter kasir & owner (menyusul, M3) |
| `spikes/printer/` | App uji cetak struk Bluetooth 58mm (M1) |
| `docs/` | ADR, panduan uji, dokumentasi API |
| `PROJECT-SCOPE.md` | Ledger kompetensi & cek keamanan — wajib hijau sebelum go-live |

## Menjalankan backend (development)

Prasyarat: Docker Desktop.

```bash
docker compose up -d --build
docker compose exec api composer install
docker compose exec api php artisan migrate:fresh --seed
```

- API: `http://localhost:8000/api/v1` (tablet di Wi-Fi yang sama: `http://<IP-laptop>:8000/api/v1`)
- PostgreSQL: `localhost:5433`. App memakai role `berrybrew_app` (bukan superuser, supaya RLS berlaku).
- Kredensial dev BerryBrew diambil dari `SEED_*` di `backend/.env`. Jika kosong, dibuat acak dan
  **ditampilkan sekali** di output `db:seed`.

Test (memakai database `berrybrew_test`):

```bash
docker compose exec api php artisan test
```

Format kode:

```bash
docker compose exec api ./vendor/bin/pint
```

## Menjalankan Flutter

Flutter SDK ada di `C:\src\flutter` (tambahkan `C:\src\flutter\bin` ke PATH).

```bash
cd spikes/printer && flutter test && flutter build apk --release --split-per-abi
```

Catatan Windows: project di drive `D:` dan pub cache di `C:` membuat cache inkremental Kotlin gagal.
Setiap project Flutter di repo ini memasang `kotlin.incremental=false` di `android/gradle.properties`.

## Alur autentikasi (ringkas)

1. Owner mendaftarkan tablet sekali: `POST /devices/register` (email + password), menghasilkan **token perangkat**.
2. Tablet menampilkan staf: `GET /auth/staff` (token perangkat).
3. Kasir/owner login PIN: `POST /auth/pin`, menghasilkan **token user** (16 jam, terikat ke tablet itu).
4. Semua operasi POS memakai token user. Tenant selalu ditentukan server dari token, tidak pernah dari klien.

Detail keputusan: [`docs/adr/0001-fondasi-arsitektur.md`](docs/adr/0001-fondasi-arsitektur.md).
