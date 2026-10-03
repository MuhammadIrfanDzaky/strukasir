# M1 — Uji Printer di Kedai (go/no-go)

App uji: `spikes/printer`. File APK ada di `spikes/printer/build/app/outputs/flutter-apk/`:
- `app-armeabi-v7a-release.apk` (13 MB): coba ini dulu, cocok untuk hampir semua tablet murah.
- `app-arm64-v8a-release.apk` (16 MB): pakai ini jika yang pertama tidak bisa dipasang.

Package yang dipakai: `print_bluetooth_thermal` (Bluetooth Classic SPP, UUID `00001101`) +
`esc_pos_utils_plus` (perintah ESC/POS, kertas 58mm).

## Persiapan
1. Kirim APK ke tablet (WA ke diri sendiri / Google Drive / kabel USB), buka, izinkan "Install unknown apps".
2. Pastikan printer iware sudah di-pair di *Settings → Bluetooth* tablet.
   Catat nama printer yang muncul: `______________`
3. **Tutup app Kloa** saat uji, supaya tidak berebut koneksi Bluetooth dengan printer.

## Langkah uji
| # | Uji | Hasil yang diharapkan | Lolos? |
|---|---|---|---|
| 1 | Tekan "Muat printer terpasang", pilih printer iware | Log: `Terhubung` | |
| 2 | Uji lebar 32 kolom | Baris angka `1234…9012` muat persis 1 baris, tidak turun | |
| 3 | Struk LUNAS | Rapi, angka rata kanan, nama produk panjang terbungkus rapi | |
| 4 | Struk BELUM BAYAR | Tercetak dengan tulisan `*** BELUM DIBAYAR ***` | |
| 5 | Checker barista | Tanpa harga, modifier & catatan terbaca | |
| 6 | Layar tablet mati 1 menit, nyalakan, cetak struk | Tetap tercetak (boleh ada log reconnect) | |
| 7 | Printer dimatikan lalu dinyalakan, cetak struk | Reconnect otomatis lalu tercetak | |
| 8 | Cetak struk LUNAS 10× berturut-turut | Semua tercetak, tidak ada yang hilang/terpotong | |
| 9 | Catat waktu cetak di log (ms) | Di bawah ±3 detik per struk | |

Foto hasil cetak no. 2, 3, dan 5 serta screenshot layar log, lalu kirim ke developer.

## Keputusan
- **Semua lolos → GO:** lanjut M2 (fondasi backend) dengan stack ini.
- **No. 2 gagal (lebar beda):** ganti `kLineWidth` (kemungkinan 30 atau 42), bukan masalah besar.
- **No. 1/6/7 gagal:** coba package alternatif sebelum lanjut. Jangan lanjut membangun POS di atas print yang tidak andal.
