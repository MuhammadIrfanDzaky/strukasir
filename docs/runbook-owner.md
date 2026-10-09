# Panduan Harian Strukasir

Untuk owner & kasir. Simpan di dekat meja kasir.

## Setiap hari

**Buka toko**
1. Nyalakan tablet dan printer. Pastikan Bluetooth tablet menyala.
2. Buka app **Strukasir**, pilih nama Anda, lalu masukkan PIN.
3. Ketuk **Buka shift** di kanan atas, lalu isi uang tunai yang ada di laci (modal awal).

**Melayani pesanan**
1. Pilih kategori (atau **Semua**), lalu ketuk produk. Pilih suhu/gula/tambahan, lalu ketuk **Tambah**.
2. Isi **Nama pelanggan / meja** (wajib). Ketuk item di keranjang untuk menambah catatan
   ("es dipisah") atau menghapusnya.
3. Ketuk **Cek pesanan** untuk membacakan ulang pesanan ke pelanggan (hanya tampil di layar, tidak dicetak).
4. Ketuk **Bayar**, lalu pilih metode:
   - **Tunai**: ketuk nominal uang dari pelanggan. Kembalian muncul besar di layar.
   - **QRIS**: tunggu **notifikasi dana masuk di aplikasi merchant QRIS**, baru ketuk *Konfirmasi diterima*.
     Nama Anda tercatat sebagai yang mengonfirmasi.
   - **Debit**: konfirmasi setelah mesin EDC menyatakan berhasil.
5. Struk pelanggan tercetak otomatis.

**Member / pelanggan**: ketuk ikon cari (🔍) di kolom nama → cari nama, kode member (M0001), atau beberapa
angka no HP → pilih. Belum terdaftar? Ketuk **Pelanggan baru** (nama + no HP, minta izin pelanggan dulu).
Kolom nama otomatis terisi nama member (boleh diganti, mis. "Meja 5"); catatan pelanggan (alergi, selera)
tampil di keranjang. Kode member tercetak di struk (no HP tidak pernah dicetak).

**Bayar nanti (Open Bill)**: ketuk **Open Bill** di bawah keranjang. Order disimpan tanpa mencetak apa pun.
Untuk menambah pesanan atau membayar, ketuk **Open Bill** di atas keranjang dan pilih order-nya:
- pelanggan pesan lagi → tambah produk, lalu ketuk **Simpan Bill**;
- pelanggan selesai → ketuk **Bayar** (Close Bill), struk tercetak.

**Logo & teks struk (owner)**: menu **Pengaturan** → **Atur struk & logo**. Pilih gambar logo (otomatis diubah
jadi hitam-putih; ketuk *Balik warna* atau geser *Ketebalan* bila hasilnya kurang pas), isi nama kedai,
alamat, dan pesan penutup. Pratinjau di layar sama dengan hasil cetak. Ketuk **Simpan**.

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
| Printer tidak terhubung sama sekali | Menu **Pengaturan** → *Tampilkan printer ter-pair* → pilih printer → *Tes cetak*. Bila tidak ada di daftar, pair ulang di *Pengaturan → Bluetooth* tablet. |
| **Internet mati** | Menu tetap tampil, tapi pembayaran perlu internet. Nyalakan **hotspot HP** dan sambungkan tablet. Jangan tekan "Bayar" berkali-kali: sistem aman dari pembayaran dobel, tapi tunggu sampai sinyal kembali. |
| "Harga menu berubah" | Menu sudah diperbarui otomatis. Periksa total lalu tekan *Bayar* lagi. |
| "Akun terkunci" | Terjadi setelah 5× PIN salah. Tunggu 5 menit. |
| Owner **lupa password** | Di tablet baru: **Sudah punya akun? Masuk → Lupa password?** → kode dikirim ke email owner → isi kode & password baru. Bila email tidak sampai (cek folder spam), hubungi developer. |
| Owner **lupa PIN** | Hubungi developer (lihat kontak di bawah). |
| **Pindahkan / jual tablet** (atau ganti ke usaha lain) | Di layar pilih nama: **Ganti usaha / keluarkan tablet** → PIN owner. Atau saat login owner: **Pengaturan → Tablet ini → Keluarkan tablet dari usaha**. Tablet kembali ke layar awal (Daftar / Masuk); data transaksi tetap di server. |
| **Tambah tablet** | Pasang app di tablet baru → **Sudah punya akun? Masuk** → email & password owner. Nama tablet otomatis (Tablet 2, 3, …). |
| Daftarkan tablet baru, diminta **Kode 2FA** | Buka aplikasi authenticator di HP owner, ketik 6 digit kode *Strukasir*. Kode berganti tiap 30 detik; bila ditolak, tunggu kode berikutnya. |
| **HP owner hilang / ganti HP** | Hubungi developer: 2FA dimatikan, password direset, lalu 2FA dipasang ulang di HP baru. Tablet yang sudah terdaftar tetap jalan. |
| "Perbarui aplikasi" | Ketuk *Unduh versi terbaru*, pasang, lalu buka lagi. |
| Selisih kas di tutup shift | Cocokkan dengan **Laporan** (per metode bayar) dan riwayat void hari itu. |

## Dashboard (owner)

Menu **Dashboard** (di HP: *Laporan*) → *Hari ini / 7 hari / 30 hari / Bulan ini*.

- **Angka utama**: penjualan, transaksi, rata-rata per transaksi, **laba kotor** (+ margin), dengan naik/turun
  dibanding periode sebelumnya yang sama panjang (mis. 7 hari ini vs 7 hari sebelumnya). Di bawahnya: HPP,
  diskon, service, pajak, void.
- **Grafik**: tren penjualan harian, jam ramai, hari tersibuk, metode bayar, penjualan per kategori, produk
  terlaris (dengan laba), dan kasir. Sentuh grafik untuk melihat angka persisnya.
**Cocokkan total QRIS** dengan mutasi di aplikasi merchant QRIS minimal seminggu sekali.

- **Laba kotor** = penjualan − pajak − modal (HPP). Modal diambil dari harga modal produk **saat transaksi**,
  jadi mengubah modal tidak mengubah laporan lama. Bila muncul peringatan "belum punya harga modal",
  isi modal produk tersebut di Kelola Menu.

## Pelanggan / member (owner)

Menu **Pelanggan** (di HP: *Member*; Pengaturan pindah ke menu akun di kanan atas).

- **Cari & kelompok**: cari nama, kode, atau no HP. Kelompok: **Baru** (terdaftar 30 hari terakhir),
  **Setia** (belanja 5× atau lebih dan masih datang 30 hari terakhir), **Menghilang** (pernah belanja, tapi
  tidak datang lebih dari 30 hari — saatnya disapa). Urutkan menurut nama, terakhir datang, belanja terbanyak.
- **Detail**: total belanja, jumlah kunjungan, rata-rata, terakhir datang, produk favorit, order terakhir.
  Hanya order lunas yang dihitung (void tidak).
- **Ubah**: nama, no HP, tanggal lahir, catatan. Kode member tetap.
- **Hapus data pelanggan** (bila pelanggan memintanya, sesuai UU PDP): nama, no HP, tanggal lahir, catatan,
  dan nama di riwayat order dihapus permanen. Angka penjualan tetap ada di laporan. Tidak bisa dibatalkan.
- **Import CSV**: kolom *Nama* (wajib), *No HP*, *Tanggal Lahir*, *Catatan*. No HP sama = diperbarui.
- **Dashboard**: porsi penjualan member vs non-member, member baru vs kembali, pelanggan teratas.
- Kasir hanya bisa mencari & mendaftarkan; no HP tampil tersamar (0812****7890), tanpa total belanja.

## Fitur (owner)

Menu **Pengaturan → Atur fitur**: nyalakan hanya yang dipakai supaya layar kasir ringkas. Semua tablet
ikut berubah. Mematikan fitur tidak menghapus data.

- **Nama pelanggan / meja**: mati → kolom nama hilang dari kasir (cocok untuk gerobak / takeaway).
  Open Bill butuh fitur ini, jadi ikut mati.
- **Open Bill**: tidak bisa dimatikan selama masih ada bill yang belum dibayar.
- **Varian produk**: mati → produk langsung masuk keranjang tanpa pilihan suhu/gula/tambahan.
- **Diskon**, **Bayar dengan beberapa metode**: tombolnya hilang dari kasir saat dimatikan.
- **Pelanggan / member**: data pelanggan, kode member, riwayat belanja. Saklar **No HP pelanggan wajib**:
  nyala = pelanggan baru harus punya no HP (tidak bisa dobel); mati = boleh nama saja.
- **Pajak & service**: isi persen (mis. PB1 10%, service 5%); 0 = tidak dipungut. Untuk tiap tarif yang
  diisi, pilih **Harga menu sudah termasuk pajak / service**: nyala = total sama dengan harga menu dan
  struk menulis "Termasuk pajak 10%"; mati = ditambahkan di atas harga. Persen ikut tercetak di struk.

Saat daftar, fitur & kategori awal disiapkan otomatis (bisa diubah kapan saja):

| Jenis usaha saat daftar | Disiapkan |
|---|---|
| **Makanan & minuman**, cara jualan *Bawa pulang saja* | Tanpa nama pelanggan/meja & Open Bill (kasir cepat) |
| **Makanan & minuman**, *Makan di tempat* / *Keduanya* | Nama pelanggan / meja wajib, Open Bill aktif |
| Kafe, restoran, warung/gerobak, minuman | Varian produk aktif (suhu, gula, level pedas, topping) |
| **Jasa** (laundry, bengkel, dll.) & **Kecantikan** (salon, spa, dll.) | Nama pelanggan wajib, Open Bill aktif (bayar saat ambil / setelah layanan) |
| **Retail** & **Kesehatan** (toko, apotek, dll.) | Tanpa nama pelanggan & Open Bill (kasir cepat) |
| Semua | Diskon & bayar beberapa metode aktif; pajak & service mati sampai persen diisi |
| Kategori awal | Sesuai jenis usaha, mis. laundry: Kiloan/Satuan; apotek: Obat Bebas/Vitamin & Suplemen/Alat Kesehatan (masih kosong) |

## Kelola menu (owner)

- **Kode, modal, favorit**: ketuk produk di **Kelola Menu**. Isi *Kode produk* (mis. BB03), *Modal (HPP)*
  (margin langsung terlihat), dan nyalakan *Favorit* agar produk muncul di filter **Favorit** layar kasir.
- **Tambahan berjumlah** (mis. Extra shot x2): Kelola Menu → grup pilihan → nyalakan *Boleh pilih lebih
  dari 1 (jumlah)*, atur *Maksimal per pilihan* dan *Maksimal total jumlah*. Di kasir, pilihan grup ini
  memakai tombol − jumlah +.
- **Cari**: kotak cari di Kelola Menu dan ikon cari di layar kasir mencari nama atau kode produk.
- **Import CSV** (pindah dari POS lain / isi menu banyak sekaligus): **Kelola Menu** → **Import CSV**.
  Judul kolom minimal *Nama Produk* dan *Harga Jual*; opsional *Kategori*, *Kode Produk*, *Modal*, *Aktif*,
  *Favorit*. Produk dengan kode/nama yang sama diperbarui, sisanya ditambahkan, dan kategori baru dibuat
  otomatis. Ringkasan tampil dulu sebelum disimpan; bila ada baris yang salah, tidak ada yang tersimpan.

## Kontak

- Developer / support: ____________________ (WA) — jam layanan: ____________
- Data dicadangkan otomatis setiap hari pukul 03.00 WIB.
