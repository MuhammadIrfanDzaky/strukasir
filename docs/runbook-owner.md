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

**Stempel / poin & hadiah** (bila program loyalitas berjalan): saldo member tampil di keranjang, begitu
juga perkiraan "dapat +2 stempel". Untuk menukar, ketuk **Tukar hadiah** → pilih hadiah (yang saldonya
kurang tidak bisa dipilih). Hadiah *gratis produk* butuh produknya sudah ada di keranjang; yang digratiskan
1 porsi harga dasar (tambahan seperti extra shot tetap dibayar). Hadiah *potongan* tidak bisa digabung
dengan diskon order. Stempel baru tercatat & hadiah baru terpotong saat **Bayar**; struk mencetak dapat,
ditukar, dan saldo. Order di-void → stempelnya ditarik dan hadiahnya kembali ke saldo member.

**Tingkat member** (Silver, Gold, …): lencana tingkat tampil di samping nama member. Diskon tingkat
otomatis masuk ke setiap item yang belum didiskon ("Diskon member"); item yang sudah diberi diskon manual
atau hadiah gratis tidak ikut. Bila muncul "Tingkat member pelanggan ini berubah", lepas member lalu pilih
lagi (tingkatnya baru saja naik/turun).

**Kasbon** (bila fitur *Kasbon* aktif): pilih member dulu, lalu di dialog bayar pilih **Kasbon** (boleh
dibagi: sebagian tunai, sisanya kasbon). Dialog menampilkan sisa kasbon sekarang, sesudahnya, dan batasnya;
bila lewat batas, owner memasukkan PIN. Struk mencetak "Sisa kasbon". Kasbon tidak menambah uang di laci.
- **Pelunasan**: pilih member → di keranjang ketuk **Bayar kasbon** (atau owner: Pelanggan → detail →
  *Catat pelunasan*). Boleh dicicil. Tunai masuk laci dan ikut "kas seharusnya" saat tutup shift; bukti
  pelunasan tercetak.

**Struk via WhatsApp** (bila fitur *Pesan WhatsApp* aktif & member punya no HP): setelah bayar, ketuk
**Struk via WA** di layar Lunas (atau Riwayat → order → *Struk via WA*). WhatsApp terbuka dengan struk siap
kirim; tekan kirim. Butuh WhatsApp terpasang di tablet/HP (gratis, tanpa langganan WA Business API).

**Promo & voucher**: promo yang sedang berjalan langsung memotong harga item di keranjang (nama promonya
tertulis). Voucher: ketuk **Pakai voucher** di bawah subtotal → ketik kodenya. Voucher tidak bisa digabung
dengan diskon order atau hadiah potongan; bila belanja belum mencapai minimal, keranjang memberi tahu.

**Bayar nanti (Open Bill)**: ketuk **Open Bill** di bawah keranjang. Order disimpan tanpa mencetak apa pun.
Untuk menambah pesanan atau membayar, ketuk **Open Bill** di atas keranjang dan pilih order-nya:
- pelanggan pesan lagi → tambah produk, lalu ketuk **Simpan Bill**;
- pelanggan selesai → ketuk **Bayar** (Close Bill), struk tercetak.

**Tiket bar / dapur**: menu **Pengaturan → Atur tiket bar / dapur** (per tablet). Tambah stasiun, mis. *Bar*
(kategori minuman, printer struk yang sama) dan *Dapur* (kategori makanan, printer kedua yang sudah di-pair).
Saat order disimpan (Open Bill) atau dibayar, item baru tercetak sebagai tiket tanpa harga; tambahan pesanan di
Open Bill bertanda **TAMBAHAN**. Tiket hilang / printer sempat mati: **Riwayat → order → Cetak tiket**.
Dengan printer kedua, tablet berpindah sambungan Bluetooth otomatis (beberapa detik lebih lama).

**Logo & teks struk (owner)**: menu **Pengaturan** → **Atur struk & logo**. Pilih gambar logo (otomatis diubah
jadi hitam-putih; ketuk *Balik warna* atau geser *Ketebalan* bila hasilnya kurang pas), isi nama kedai,
alamat, dan pesan penutup. Pratinjau di layar sama dengan hasil cetak. Ketuk **Simpan**.

**Kas keluar / masuk** (di luar penjualan): ketuk chip shift di kanan atas → **Kas keluar** (beli bahan,
gas/air/listrik, upah harian, setor ke owner) atau **Kas masuk** (tambah uang kecil). Isi nominal & keterangan.
Semua ikut dihitung di "kas seharusnya" saat tutup shift. Salah catat: chip shift → *Catatan kas shift ini* →
batalkan (kasir butuh PIN owner). Di Dashboard muncul **Pengeluaran** dan **Laba bersih** (laba kotor −
pengeluaran; setor ke owner tidak dihitung sebagai biaya).

**Tutup toko**
1. Hitung semua uang tunai di laci, termasuk modal awal.
2. Ketuk chip shift di kanan atas → **Tutup shift**, lalu isi jumlah yang dihitung.
3. App menampilkan **selisih** (lebih/kurang). Ketuk **Cetak laporan shift** dan simpan kertasnya.
4. Laporan shift (penjualan, metode bayar, kas keluar, selisih, terlaris, total hari ini) **otomatis terkirim ke
   email owner** bila email sudah diverifikasi. Untuk WhatsApp, ketuk **Kirim ke WA owner** lalu tekan kirim.
   Atur di Pengaturan → Fitur → *Laporan tutup shift ke owner* (nomor WA kosong = no HP saat daftar).

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
**Unduh ke Excel**: Dashboard → ikon unduh (⤓) → pilih *Penjualan per transaksi*, *per item*, *Rekap pajak
(PB1) per hari*, atau *Kas keluar/masuk* untuk periode yang sedang dilihat. File CSV terunduh lewat browser ke
folder **Download** dan bisa dibuka di Excel / Google Sheets. Tautannya hanya berlaku 10 menit.

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

## Program loyalitas (owner)

Menu **Pengaturan → Program loyalitas** (fitur *Program loyalitas* harus aktif, butuh *Pelanggan*).

- **Cara dapat** (pilih satu): *stempel per item* (semua produk atau kategori tertentu, mis. hanya minuman),
  *stempel per transaksi* (boleh dengan minimal belanja), atau *poin per belanja* (mis. 1 poin tiap Rp10.000).
- **Hadiah**: buat daftar sendiri — *gratis produk*, *potongan Rp*, atau *potongan %* — dengan harga
  stempel/poin masing-masing. Contoh: "10 stempel = gratis 1 Kopi Susu Aren".
- **Masa berlaku**: tidak pernah hangus, atau hangus bila member tidak belanja 3/6/12/24 bulan.
- **Program berjalan** mati → tidak ada stempel baru & hadiah tidak bisa ditukar (saldo tetap tersimpan).
- **Sesuaikan saldo** (Pelanggan → detail → *Sesuaikan*): tambah/kurangi dengan alasan, mis. pindahan kartu
  stempel kertas. Semua perubahan tercatat di riwayat stempel pelanggan.
- **Dashboard**: stempel/poin keluar vs ditukar, nilai hadiah, hadiah terpopuler.

## Pesan WhatsApp (owner)

- **Kirim pesan**: Pelanggan → ikon chat (*Kirim pesan WA*) → tab **Ulang tahun** (hari ini s/d 7 hari ke
  depan), **Menghilang** (>30 hari tidak datang), **Berkasbon**. Ketuk **WA** → WhatsApp terbuka dengan pesan
  siap kirim. Yang sudah dikirimi bertanda "Terkirim …" supaya tidak dobel.
- **Per pelanggan**: detail pelanggan → ikon chat → pilih sapaan / ulang tahun / sapa pelanggan lama /
  pengingat kasbon.
- **Ubah teks**: Pengaturan → *Pesan WhatsApp*. Isian otomatis: {nama} {kedai} {kode} {tingkat} {stempel}
  {sisa_kasbon} {struk} {total} {nomor}. *Teks bawaan* mengembalikan teks awal.
- Kasir hanya bisa mengirim struk digital; pesan lain hanya owner. Semua pesan yang disiapkan tercatat.

## Promo & voucher (owner)

Menu **Pengaturan → Atur promo & voucher** (fitur *Promo & voucher*).

- **Promo otomatis**: *Diskon %*, *Rp per item*, atau *Beli X gratis Y* (item gratis = harga dasar produk yang
  sama). Untuk semua produk, kategori, atau produk tertentu. Jadwal: hari (Sen–Min), jam (mis. happy hour
  14:00–17:00; boleh melewati tengah malam), dan tanggal berakhir. Tanda **Berjalan** = sedang aktif sekarang.
- Per item dipakai **potongan terbesar** antara promo dan diskon tingkat member; item yang sudah didiskon
  manual / hadiah tidak ikut. Potongan promo & voucher tidak butuh PIN owner.
- **Voucher**: kode (mis. HEMAT10), diskon % (boleh dengan batas maksimal) atau Rp, minimal belanja, kuota
  pemakaian, tanggal berakhir. Kuota dihitung dari transaksi lunas; transaksi yang di-void mengembalikan kuota.
- Dashboard: promo & voucher yang terpakai beserta total potongannya; struk menulis nama promo / kode voucher.

## Kasbon (owner)

- **Batas default** per member: Pengaturan → Fitur → *Kasbon* (kosong = tanpa batas). Batas khusus per
  member: Pelanggan → detail → *Kasbon* → *Batas* (0 = tidak boleh kasbon).
- **Daftar yang berkasbon**: Pelanggan → kelompok *Berkasbon*, atau urutkan *Kasbon terbesar*.
- **Salah catat pelunasan**: Pelanggan → detail → riwayat kasbon → tombol batalkan (↶) + alasan. Bila tunai,
  uangnya dianggap keluar dari laci shift yang sedang buka.
- **Void order kasbon** otomatis mengurangi kasbon member (tidak ada uang keluar).
- Data pelanggan yang masih berkasbon tidak bisa dihapus sebelum lunas.
- **Dashboard**: piutang sekarang, kasbon baru & pelunasan di periode, member dengan kasbon terbesar.
- **Tutup shift**: laporan menampilkan "Kasbon (belum dibayar)" dan "Pelunasan kasbon tunai".

## Tingkat member (owner)

Menu **Pengaturan → Tingkat member** (fitur *Tingkat member* harus aktif, butuh *Pelanggan*).

- **Cara naik tingkat**: total belanja atau jumlah kunjungan, dihitung dari 3/6/12/24 bulan terakhir atau
  sepanjang waktu. Tingkat naik otomatis, dan turun lagi bila belanjanya keluar dari jendela waktu.
- **Tiap tingkat**: nama, ambang (mis. mulai Rp500.000), diskon otomatis (0–50%), pengali stempel/poin
  (1×/2×/3×), dan warna lencana. Maksimal 6 tingkat.
- **Kunci manual**: Pelanggan → detail → *Tingkat member* → *Ubah* → pilih tingkat (mis. VIP keluarga)
  atau *Otomatis dari belanja*. Halaman yang sama menampilkan kemajuan menuju tingkat berikutnya.
- Diskon tingkat tidak butuh PIN owner walau melebihi batas diskon kasir.
- Daftar pelanggan bisa difilter per tingkat; dashboard menampilkan penjualan per tingkat.

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
- **Program loyalitas**: stempel/poin & hadiah untuk member (butuh *Pelanggan / member*).
- **Promo & voucher**: promo otomatis terjadwal & voucher kode.
- **Pesan WhatsApp**: struk digital & pesan ke member lewat WhatsApp (butuh *Pelanggan*).
- **Kasbon (bayar nanti)**: member boleh berutang dengan batas; pelunasan di kasir (butuh *Pelanggan*).
- **Tingkat member**: Silver/Gold dst. dengan diskon & pengali stempel (butuh *Pelanggan / member*).
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
