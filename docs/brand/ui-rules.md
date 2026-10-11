# Aturan UI Strukasir

Token warna & tipografi ada di `app/lib/core/theme/tokens.dart`. Dokumen ini mengatur **cara memakainya**,
supaya layar tetap tenang dan profesional — bukan ramai warna & ikon.

## Warna

- **Dasar netral (slate).** Latar, kartu putih bergaris tipis, teks `ink` / `inkMuted`.
- **Indigo (`primary`) hanya untuk aksi & pilihan aktif:** tombol utama, tab/chip terpilih, satu kartu KPI utama,
  satu seri / batang yang disorot di grafik. Bukan untuk harga, judul, ikon hiasan, atau garis penanda.
- **Hijau / merah / amber hanya untuk status yang perlu perhatian:** lunas/void, habis, stok minus/menipis,
  kas kurang/lebih, naik/turun di laporan, rugi. Bukan untuk diskon/promo biasa atau dekorasi.
- **Grafik kategori** (metode bayar) boleh memakai palet grafik (`ChartColors`) — selalu dengan label & nilai.
- Tidak ada kotak ikon berlatar warna, garis warna di judul bagian, atau warna berbeda per kelompok.

## Ikon

- **Boleh:** navigasi (rail / tab bar), tombol ikon tanpa teks (cari, unduh, muat ulang, ubah, hapus, tutup),
  ikon fungsional di kolom isian (cari), status penting (centang sukses bayar, titik shift).
- **Tidak:** ikon di depan baris daftar/pengaturan, di judul panel/kartu/dialog, di KPI, di badge, di tombol yang
  sudah berlabel teks, atau di judul bagian.

## Hierarki

- Bedakan lewat **ukuran, tebal huruf, abu-abu, jarak, dan garis pemisah** — bukan warna atau ikon.
- Judul bagian: label kapital kecil abu-abu (`AppOverline`). Judul panel: `AppType.title`. Keterangan: `caption` abu-abu.
- Angka penting besar & tebal (`headline` / `moneyLg`); label di atasnya kecil abu-abu.
- Kartu datar: putih, garis `line` 1px, tanpa bayangan bertumpuk. Panel berdampingan sama tinggi.
- Badge hanya teks; netral kecuali status.
