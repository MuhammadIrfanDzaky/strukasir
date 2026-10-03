# Panduan Harian BerryBrew POS

Untuk owner & kasir. Simpan di dekat meja kasir.

## Setiap hari

**Buka toko**
1. Nyalakan tablet dan printer. Pastikan Bluetooth tablet menyala.
2. Buka app **BerryBrew POS**, pilih nama Anda, lalu masukkan PIN.
3. Ketuk **Buka shift** di kanan atas, lalu isi uang tunai yang ada di laci (modal awal).

**Melayani pesanan**
1. Pilih kategori, lalu ketuk produk. Pilih suhu/gula/tambahan, lalu ketuk **Tambah**.
2. Isi **Nama pelanggan / meja** bila perlu. Ketuk item di keranjang untuk menambah catatan
   ("es dipisah") atau menghapusnya.
3. Ketuk **Bayar**, lalu pilih metode:
   - **Tunai**: ketuk nominal uang dari pelanggan. Kembalian muncul besar di layar.
   - **QRIS**: tunggu **notifikasi dana masuk di aplikasi merchant QRIS**, baru ketuk *Konfirmasi diterima*.
     Nama Anda tercatat sebagai yang mengonfirmasi.
   - **Debit**: konfirmasi setelah mesin EDC menyatakan berhasil.
4. Struk tercetak otomatis, dan checker untuk barista juga ikut tercetak.

**Bayar nanti (open bill)**: ketuk **Simpan (belum bayar)**. Bill dan checker tercetak. Untuk membayar,
ketuk **Belum dibayar** di atas keranjang, pilih order-nya, lalu ketuk **Bayar**.

**Tutup toko**
1. Hitung semua uang tunai di laci, termasuk modal awal.
2. Ketuk chip shift di kanan atas → **Tutup**, lalu isi jumlah yang dihitung.
3. App menampilkan **selisih** (lebih/kurang). Ketuk **Cetak laporan shift** dan simpan kertasnya.

## Diskon & pembatalan

- **Diskon**: ketuk item → *Diskon item*, atau ketuk *Diskon order*. Kasir boleh memberi diskon sampai
  **10%**. Di atas itu, owner harus memasukkan PIN di tablet.
- **Batal / salah input**: buka **Riwayat** → pilih order → **Void** → isi alasan. Kasir butuh PIN owner.
  - Order yang **sudah dibayar** akan dicatat sebagai refund. Kembalikan uangnya ke pelanggan (tunai dari
    laci, atau QRIS/debit secara manual) **sebelum** tutup shift.
- Semua diskon besar dan void tercatat: siapa, kapan, alasan, dan siapa yang menyetujui.

## Kalau ada masalah

| Masalah | Yang dilakukan |
|---|---|
| **Struk tidak keluar** | Transaksi **tetap tersimpan**. Cek printer menyala, kertas ada, dan dekat tablet. Ketuk **Cetak ulang** di pesan yang muncul, atau buka **Riwayat** → order → **Cetak ulang**. |
| Printer tidak terhubung sama sekali | Menu **Printer** → *Tampilkan printer ter-pair* → pilih printer → *Tes cetak*. Bila tidak ada di daftar, pair ulang di *Pengaturan → Bluetooth* tablet. |
| **Internet mati** | Menu tetap tampil, tapi pembayaran perlu internet. Nyalakan **hotspot HP** dan sambungkan tablet. Jangan tekan "Bayar" berkali-kali: sistem aman dari pembayaran dobel, tapi tunggu sampai sinyal kembali. |
| "Harga menu berubah" | Menu sudah diperbarui otomatis. Periksa total lalu tekan *Bayar* lagi. |
| "Akun terkunci" | Terjadi setelah 5× PIN salah. Tunggu 5 menit. |
| Owner lupa password / PIN | Hubungi developer (lihat kontak di bawah). |
| "Perbarui aplikasi" | Ketuk *Unduh versi terbaru*, pasang, lalu buka lagi. |
| Selisih kas di tutup shift | Cocokkan dengan **Laporan** (per metode bayar) dan riwayat void hari itu. |

## Laporan (owner)

Menu **Laporan** → *Hari ini / 7 hari / Bulan ini*: penjualan, rata-rata per order, per metode bayar,
per kasir, produk terlaris, dan void.
**Cocokkan total QRIS** dengan mutasi di aplikasi merchant QRIS minimal seminggu sekali.

## Kontak

- Developer / support: ____________________ (WA) — jam layanan: ____________
- Data dicadangkan otomatis setiap hari pukul 03.00 WIB.
