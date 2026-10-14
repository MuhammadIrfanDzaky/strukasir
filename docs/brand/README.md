# Merek Strukasir

Lembar ringkas: [`strukasir-brand-guide.png`](strukasir-brand-guide.png). Semua aset di folder ini dibuat ulang dengan:

```
python tools/brand/build.py --shots docs/brand/visuals/source
```

Bentuk logo bersumber dari `strukasir-mark.svg` (kertas struk bergerigi + huruf S + titik amber) dan
`strukasir-wordmark.svg` (Plus Jakarta Sans ExtraBold, sudah jadi outline — tidak butuh font).

## 1. Logo — 4 variasi

| Variasi | Isi | Pakai untuk | Folder |
|-|-|-|-|
| **Primary** | simbol + STRUKASIR mendatar | default: situs, struk, email, kop surat, presentasi | `logo/primary/` |
| **Secondary** | simbol di atas, nama di bawah | ruang persegi/tegak: poster, stiker, sampul, layar pembuka | `logo/secondary/` |
| **Simplified** | STRUKASIR saja | tempat yang sudah jelas mereknya / sangat sempit memanjang: footer, watermark, merchandise | `logo/simplified/` |
| **Sub-mark** | simbol struk saja | ikon & avatar: foto profil medsos, favicon, stempel, pin | `logo/submark/` |

Setiap variasi tersedia dalam 4 versi (SVG untuk cetak/desain, PNG transparan untuk pakai cepat):

- `color` — di atas latar putih/terang (utama)
- `reversed` — di atas latar indigo
- `mono-dark` — satu warna gelap (cetak hitam-putih, stempel, fotokopi)
- `mono-light` — satu warna putih di atas latar gelap/foto

Ikon aplikasi: `logo/app-icon/` (SVG + PNG 32/180/192/512/1024). Logo email: `email/strukasir-email-logo.png`.

**Aturan:** beri ruang kosong di sekeliling logo minimal setinggi huruf S. Primary minimal 96 px / 25 mm
lebarnya, sub-mark minimal 24 px. Jangan diubah warna di luar palet, diregangkan, diberi bayangan/efek,
atau diletakkan di atas foto ramai tanpa versi `mono-light`.

## 2. Warna — 4 peran

| Peran | Nama | Hex | Pakai |
|-|-|-|-|
| Primary | Indigo | `#3730A3` | tombol utama, pilihan aktif, latar merek |
| Accent | Amber | `#F59E0B` | titik logo, CTA paket — sedikit saja |
| Neutral | Slate | `#F8FAFC` (garis `#E2E8F0`) | latar halaman & kartu |
| Dark | Ink | `#0F172A` | teks utama, latar gelap |

Variabel CSS: `colors/strukasir-colors.css`. Hijau/merah/kuning hanya untuk status (lihat `ui-rules.md`).

## 3. Font — 4 peran (`typography/`)

| Peran | Font | Pakai |
|-|-|-|
| Display | Plus Jakarta Sans ExtraBold 800 | judul, iklan, nama merek |
| Body | Plus Jakarta Sans Regular 400 | paragraf, email |
| UI | Plus Jakarta Sans Medium / SemiBold / Bold | tombol, label, angka di app |
| Fallback | Segoe UI / Roboto / Arial | email & perangkat tanpa font merek |

File font (lisensi OFL, bebas dipakai komersial): `app/assets/fonts/`.

## 4. Iklan — 4 format (`ads/`)

| Format | Ukuran | Pakai |
|-|-|-|
| 9:16 | 1080×1920 | Story / Reels / TikTok / status WhatsApp |
| 16:9 | 1920×1080 | YouTube, banner situs, presentasi |
| 3:4 | 1080×1440 | feed Instagram (potret) |
| 1:1 | 1080×1080 | feed Instagram/Facebook, marketplace |

Pesan: "Kasir rapi, struk jelas, laporan langsung jadi." · "Mulai Rp9.900/bulan" · CTA "Coba gratis 7 hari".
Ubah teksnya di `tools/brand/build.py` (konstanta `HEADLINE`, `SUB`, `CTA`) lalu jalankan ulang.

## 5. Visual — 4 jenis (`visuals/`)

| Jenis | File | Catatan |
|-|-|-|
| Hero | `strukasir-hero.png` | visual utama: tablet berisi layar kasir |
| Tagline | `strukasir-tagline.png` | "Struk rapi, usaha naik kelas." |
| Product | `strukasir-product.png` | tablet (dashboard) + HP (kasir) |
| Texture | `strukasir-texture-indigo.png`, `strukasir-texture-light.png` | pola tepi struk bergerigi untuk latar |

Ini ilustrasi dari layar app (bukan foto). Untuk iklan berbayar, tambahkan **foto asli**: pemilik usaha
memakai tablet di kedai/laundry/warung (hero), tangan menyerahkan struk (tagline), tablet + printer di meja
kasir (product), dan detail kertas struk (texture).
