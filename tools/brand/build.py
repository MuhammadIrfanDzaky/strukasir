"""Generator aset merek Strukasir (logo, warna, tipografi, iklan, visual, panduan).

Mengikuti hierarki: 4 logo (primary, secondary, simplified, sub-mark), 4 warna (primary, accent, neutral,
dark), 4 peran font (display, body, UI, fallback), 4 format iklan (9:16, 16:9, 3:4, 1:1), 4 visual
(hero, tagline, product, texture).

Sumber bentuk logo: docs/brand/strukasir-mark.svg & strukasir-wordmark.svg (outline font, bukan teks).
Ekspor PNG memakai Chrome headless (tanpa paket tambahan).

    python tools/brand/build.py [--shots DIR]   # DIR = screenshot app (kasir-isi, laporan) untuk iklan
"""
import argparse
import base64
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'docs' / 'brand'
OUT = ROOT / 'docs' / 'brand'
FONTS = ROOT / 'app' / 'assets' / 'fonts'
CHROME = next(p for p in [
    Path(r'C:\Program Files\Google\Chrome\Application\chrome.exe'),
    Path(r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'),
    Path('/usr/bin/google-chrome'), Path('/usr/bin/chromium'),
] if p.exists())

# Palet (sama dengan app/lib/core/theme/tokens.dart)
INDIGO = '#3730A3'
INDIGO_DARK = '#312E81'
INDIGO_SOFT = '#E0E7FF'
AMBER = '#F59E0B'
SLATE_50 = '#F8FAFC'
SLATE_200 = '#E2E8F0'
SLATE_500 = '#64748B'
INK = '#0F172A'
WHITE = '#FFFFFF'


def _paths(svg_file):
    s = (SRC / svg_file).read_text(encoding='utf-8')
    return re.findall(r'<path d="([^"]+)"', s), re.findall(r'<circle ([^/]+)/>', s)


MARK_PATHS, MARK_CIRCLES = _paths('strukasir-mark.svg')
RECEIPT_D, S_D = MARK_PATHS[0], MARK_PATHS[1]
DOT = MARK_CIRCLES[0].replace('fill="#F59E0B"', '').strip()  # cx cy r
WORD_D = _paths('strukasir-wordmark.svg')[0][0]
WORD_W, WORD_H = 315, 40

# ---------------------------------------------------------------- logo
VARIANTS = {
    # nama: (kertas struk, huruf S, titik, wordmark). None = dilubangi (warna latar terlihat).
    'color': (INDIGO, WHITE, AMBER, INK),
    'reversed': (WHITE, None, AMBER, WHITE),
    'mono-dark': (INK, None, None, INK),
    'mono-light': (WHITE, None, None, WHITE),
}
VARIANT_BG = {'color': WHITE, 'reversed': INDIGO, 'mono-dark': WHITE, 'mono-light': INK}


def mark_svg(variant, uid):
    """Simbol struk (koordinat 96×96). Huruf/titik yang None dilubangi dengan mask."""
    paper, s, dot, _ = VARIANTS[variant]
    holes = [f'<path d="{S_D}" fill="#000"/>' if s is None else '', f'<circle {DOT} fill="#000"/>' if dot is None else '']
    mask = ''
    if any(holes):
        mask = (f'<defs><mask id="{uid}"><rect x="0" y="0" width="96" height="96" fill="#fff"/>{"".join(holes)}</mask></defs>')
    out = mask + f'<path d="{RECEIPT_D}" fill="{paper}"' + (f' mask="url(#{uid})"' if mask else '') + '/>'
    if s is not None:
        out += f'<path d="{S_D}" fill="{s}"/>'
    if dot is not None:
        out += f'<circle {DOT} fill="{dot}"/>'
    return out


def word_svg(variant):
    return f'<path d="{WORD_D}" fill="{VARIANTS[variant][3]}"/>'


def logo(kind, variant):
    """Kembalikan (svg, lebar, tinggi). Ukuran asli; ruang kosong di sekitar logo = bebas."""
    uid = f'k{kind}{variant}'.replace('-', '')
    if kind == 'primary':  # simbol + wordmark mendatar
        w, h = 403, 96
        body = f'<g transform="translate(-14 0)">{mark_svg(variant, uid)}<g transform="translate(98 28)">{word_svg(variant)}</g></g>'
    elif kind == 'secondary':  # simbol di atas, wordmark di bawah (tengah)
        # Simbol diperbesar 1,5× agar seimbang dengan nama di bawahnya (kertas struk ±60×76 di kotak 96).
        k = 1.5
        w, h = WORD_W, int(86 * k) + 18 + WORD_H
        body = (f'<g transform="translate({(WORD_W - 96 * k) / 2} {-8 * k}) scale({k})">{mark_svg(variant, uid)}</g>'
                f'<g transform="translate(0 {int(86 * k) + 18})">{word_svg(variant)}</g>')
    elif kind == 'simplified':  # wordmark saja
        w, h = WORD_W, WORD_H
        body = word_svg(variant)
    else:  # sub-mark: simbol struk saja (ikon, favicon, avatar)
        w, h = 64, 80
        body = f'<g transform="translate(-16 -8)">{mark_svg(variant, uid)}</g>'
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'
    return svg, w, h


# ---------------------------------------------------------------- render
def font_css():
    faces = []
    for weight, name in [(400, 'Regular'), (500, 'Medium'), (600, 'SemiBold'), (700, 'Bold'), (800, 'ExtraBold')]:
        url = (FONTS / f'PlusJakartaSans-{name}.ttf').as_uri()
        faces.append(f"@font-face{{font-family:'Plus Jakarta Sans';src:url('{url}');font-weight:{weight};}}")
    return ''.join(faces)


def render(html_body, out_png, w, h, scale=1, transparent=False, css=''):
    """Render HTML ke PNG ukuran w×h (piksel CSS) × scale."""
    out_png.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_png.with_suffix('.render.html')
    tmp.write_text(f'''<!doctype html><html><head><meta charset="utf-8"><style>{font_css()}
html,body{{margin:0;padding:0;width:{w}px;height:{h}px;overflow:hidden;background:{'transparent' if transparent else WHITE};
font-family:'Plus Jakarta Sans','Segoe UI',Roboto,Arial,sans-serif;-webkit-font-smoothing:antialiased;}}
*{{box-sizing:border-box}}{css}</style></head><body>{html_body}</body></html>''', encoding='utf-8')
    out_png.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(CHROME), '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
                    '--allow-file-access-from-files', f'--force-device-scale-factor={scale}',
                    f'--window-size={w},{h}', '--default-background-color=00000000' if transparent else '--default-background-color=FFFFFFFF',
                    f'--screenshot={out_png}', tmp.as_uri()], check=True, capture_output=True, timeout=120)
    tmp.unlink()


def img_uri(path):
    return 'data:image/png;base64,' + base64.b64encode(Path(path).read_bytes()).decode()


def svg_uri(svg):
    return 'data:image/svg+xml;base64,' + base64.b64encode(svg.encode()).decode()


# ---------------------------------------------------------------- bagian
def build_logos():
    for kind in ['primary', 'secondary', 'simplified', 'submark']:
        for variant in VARIANTS:
            svg, w, h = logo(kind, variant)
            base = OUT / 'logo' / kind / f'strukasir-{kind}-{variant}'
            base.parent.mkdir(parents=True, exist_ok=True)
            base.with_suffix('.svg').write_text(svg, encoding='utf-8')
            # PNG transparan, tinggi ±512 px (cukup untuk cetak kecil & presentasi)
            scale = max(1, round(512 / h)) if kind != 'simplified' else 6
            render(f'<img src="{svg_uri(svg)}" width="{w}" height="{h}" style="display:block">',
                   base.with_suffix('.png'), w, h, scale=scale, transparent=True)
    # Ikon aplikasi & favicon dari ikon yang sudah ada
    icon = (SRC / 'strukasir-app-icon.svg').read_text(encoding='utf-8')
    for size in [32, 180, 192, 512, 1024]:
        render(f'<img src="{svg_uri(icon)}" width="{size}" height="{size}" style="display:block">',
               OUT / 'logo' / 'app-icon' / f'strukasir-app-icon-{size}.png', size, size, transparent=True)
    shutil.copy(SRC / 'strukasir-app-icon.svg', OUT / 'logo' / 'app-icon' / 'strukasir-app-icon.svg')


def build_email_logo():
    """Logo header email (PNG, karena Gmail tidak menampilkan SVG): primary berwarna, tinggi 32 px @2x."""
    svg, w, h = logo('primary', 'color')
    out = ROOT / 'backend' / 'resources' / 'brand' / 'email-logo.png'
    render(f'<img src="{svg_uri(svg)}" width="{w}" height="{h}" style="display:block">', out, w, h, scale=2, transparent=True)
    (OUT / 'email').mkdir(exist_ok=True)
    shutil.copy(out, OUT / 'email' / 'strukasir-email-logo.png')


COLORS = [
    ('Primary', 'Indigo', INDIGO, WHITE, 'Tombol utama, pilihan aktif, latar merek'),
    ('Accent', 'Amber', AMBER, INK, 'Titik logo, CTA paket. Sedikit saja'),
    ('Neutral', 'Slate', SLATE_50, INK, 'Latar halaman & kartu, garis #E2E8F0'),
    ('Dark', 'Ink', INK, WHITE, 'Teks utama, latar gelap'),
]


def build_colors():
    cells = ''.join(f'''<div style="background:{hexv};color:{fg};padding:40px;display:flex;flex-direction:column;justify-content:space-between;
      border:{'1px solid ' + SLATE_200 if hexv == SLATE_50 else 'none'}">
      <div style="font-size:22px;font-weight:700;letter-spacing:2px;text-transform:uppercase;opacity:.8">{role}</div>
      <div><div style="font-size:52px;font-weight:800">{name}</div><div style="font-size:34px;font-weight:600;margin-top:6px">{hexv}</div>
      <div style="font-size:22px;margin-top:14px;opacity:.85">{use}</div></div></div>''' for role, name, hexv, fg, use in COLORS)
    render(f'<div style="display:grid;grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;width:1600px;height:1200px">{cells}</div>',
           OUT / 'colors' / 'strukasir-colors.png', 1600, 1200)
    (OUT / 'colors' / 'strukasir-colors.css').write_text(f''':root {{
  /* Strukasir — warna merek (sumber: app/lib/core/theme/tokens.dart) */
  --strukasir-primary: {INDIGO};     /* indigo: aksi utama & latar merek */
  --strukasir-primary-dark: {INDIGO_DARK};
  --strukasir-primary-soft: {INDIGO_SOFT};
  --strukasir-accent: {AMBER};      /* amber: titik logo & CTA paket */
  --strukasir-neutral: {SLATE_50};     /* slate: latar */
  --strukasir-line: {SLATE_200};
  --strukasir-muted: {SLATE_500};
  --strukasir-dark: {INK};        /* ink: teks & latar gelap */
}}
''', encoding='utf-8')


def build_type():
    def box(role, sample, style, note):
        return f'''<div style="border:1px solid {SLATE_200};border-radius:16px;padding:40px;display:flex;flex-direction:column;justify-content:space-between">
        <div style="font-size:20px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:{SLATE_500}">{role}</div>
        <div style="{style};color:{INK}">{sample}</div>
        <div style="font-size:20px;color:{SLATE_500}">{note}</div></div>'''
    cells = (box('Display', 'Struk rapi,<br>usaha naik kelas.', 'font-size:64px;font-weight:800;line-height:1.05',
                 'Plus Jakarta Sans ExtraBold 800 · judul, iklan, logo')
             + box('Body', 'Catat penjualan, cetak struk, dan lihat laporan harian langsung dari tablet kasir.',
                   'font-size:30px;font-weight:400;line-height:1.5', 'Plus Jakarta Sans Regular 400 · paragraf, email')
             + box('UI', '<span style="display:inline-block;background:' + INDIGO + ';color:#fff;border-radius:12px;padding:14px 26px;font-weight:700">Bayar Rp72.900</span>'
                   '<div style="margin-top:20px;font-size:26px;font-weight:600">Kopi Susu Gula Aren · Rp18.000</div>',
                   'font-size:26px', 'Plus Jakarta Sans Medium/SemiBold/Bold · tombol, label, angka')
             + box('Fallback', 'Aa Bb Cc<br>0123456789', "font-size:52px;font-family:'Segoe UI',Roboto,Arial,sans-serif;font-weight:600;line-height:1.2",
                   'Segoe UI / Roboto / Arial · email & perangkat tanpa font merek'))
    render(f'<div style="display:grid;grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;gap:28px;padding:48px;width:1600px;height:1200px;background:{SLATE_50}">{cells}</div>',
           OUT / 'typography' / 'strukasir-typography.png', 1600, 1200)


def texture_css(color, opacity, size=48):
    """Pola tepi struk bergerigi (zigzag) — tekstur khas Strukasir."""
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}"><path d="M0 {size * .7} l{size / 4} -{size / 4} '
           f'l{size / 4} {size / 4} l{size / 4} -{size / 4} l{size / 4} {size / 4}" fill="none" stroke="{color}" stroke-opacity="{opacity}" '
           f'stroke-width="3" stroke-linejoin="round"/></svg>')
    return f"url('{svg_uri(svg)}')"


def tablet(shot, width):
    """Bingkai tablet sederhana (tanpa merek pihak ketiga) berisi screenshot app."""
    return (f'<div style="width:{width}px;padding:{width * .025}px;background:{INK};border-radius:{width * .04}px;'
            f'box-shadow:0 40px 80px rgba(15,23,42,.35)"><img src="{img_uri(shot)}" style="display:block;width:100%;border-radius:{width * .012}px"></div>')


def phone(shot, width):
    return (f'<div style="width:{width}px;padding:{width * .045}px;background:{INK};border-radius:{width * .14}px;'
            f'box-shadow:0 30px 60px rgba(15,23,42,.35)"><img src="{img_uri(shot)}" style="display:block;width:100%;border-radius:{width * .09}px"></div>')


HEADLINE = 'Kasir rapi, struk jelas, laporan langsung jadi.'
SUB = 'Aplikasi kasir tablet untuk UMKM. Mulai Rp9.900/bulan.'
CTA = 'Coba gratis 7 hari'


def lockup_img(variant, height):
    svg, w, h = logo('primary', variant)
    return f'<img src="{svg_uri(svg)}" style="display:block;height:{height}px;width:{height * w / h}px">'


def build_ads(shots):
    kasir = shots / 'kasir-isi__tablet-landscape.png'
    bg = f'background:{INDIGO} {texture_css(WHITE, .07)};'
    cta = (lambda size: f'<span style="display:inline-block;background:{AMBER};color:{INK};font-weight:800;font-size:{size}px;'
                        f'border-radius:999px;padding:{size * .55}px {size * 1.2}px">{CTA}</span>')
    text = (lambda hs, ss: f'<div style="color:#fff;font-weight:800;font-size:{hs}px;line-height:1.08;letter-spacing:-.5px">{HEADLINE}</div>'
                           f'<div style="color:{INDIGO_SOFT};font-size:{ss}px;line-height:1.4;margin-top:{ss}px">{SUB}</div>')
    ads = {
        '9x16': (1080, 1920, f'''<div style="{bg}width:1080px;height:1920px;padding:110px 90px;display:flex;flex-direction:column">
            {lockup_img('reversed', 84)}<div style="margin-top:110px">{text(104, 40)}</div><div style="margin-top:56px">{cta(40)}</div>
            <div style="margin-top:auto;margin-right:-260px">{tablet(kasir, 1150)}</div></div>'''),
        '16x9': (1920, 1080, f'''<div style="{bg}width:1920px;height:1080px;padding:100px 0 100px 110px;display:flex;align-items:center;gap:80px">
            <div style="width:760px;flex:none">{lockup_img('reversed', 72)}<div style="margin-top:80px">{text(84, 34)}</div>
            <div style="margin-top:56px">{cta(34)}</div></div><div style="flex:none">{tablet(kasir, 1180)}</div></div>'''),
        '3x4': (1080, 1440, f'''<div style="{bg}width:1080px;height:1440px;padding:90px;display:flex;flex-direction:column">
            {lockup_img('reversed', 72)}<div style="margin-top:70px">{text(88, 36)}</div><div style="margin-top:44px">{cta(36)}</div>
            <div style="margin-top:auto;margin-right:-300px;margin-bottom:-160px">{tablet(kasir, 1100)}</div></div>'''),
        '1x1': (1080, 1080, f'''<div style="{bg}width:1080px;height:1080px;padding:80px;display:flex;flex-direction:column;overflow:hidden">
            {lockup_img('reversed', 60)}<div style="margin-top:56px">{text(74, 32)}</div>
            <div style="margin-top:auto;margin-right:-320px;margin-bottom:-240px">{tablet(kasir, 1000)}</div></div>'''),
    }
    for name, (w, h, html) in ads.items():
        render(html, OUT / 'ads' / f'strukasir-ad-{name}.png', w, h)


def build_visuals(shots):
    kasir = shots / 'kasir-isi__tablet-landscape.png'
    laporan = shots / 'laporan__tablet-landscape.png'
    hp = shots / 'kasir-isi__hp-portrait.png'
    v = OUT / 'visuals'
    # Hero: visual utama (situs, banner, presentasi)
    render(f'''<div style="width:1920px;height:1080px;background:{SLATE_50} {texture_css(INDIGO, .06)};display:flex;align-items:center;justify-content:center">
        {tablet(kasir, 1400)}</div>''', v / 'strukasir-hero.png', 1920, 1080)
    # Tagline: kalimat merek
    render(f'''<div style="width:1080px;height:1080px;background:{INK};padding:110px;display:flex;flex-direction:column;justify-content:space-between">
        {lockup_img('mono-light', 56)}
        <div style="color:#fff;font-weight:800;font-size:112px;line-height:1.02;letter-spacing:-1px">Struk rapi,<br>usaha naik<br>kelas<span style="color:{AMBER}">.</span></div>
        <div style="color:#CBD5E1;font-size:34px">Kasir · struk · laporan untuk UMKM</div></div>''', v / 'strukasir-tagline.png', 1080, 1080)
    # Product: tablet + HP
    render(f'''<div style="width:1920px;height:1080px;background:{INDIGO_SOFT};position:relative;overflow:hidden">
        <div style="position:absolute;left:150px;top:150px">{tablet(laporan, 1250)}</div>
        <div style="position:absolute;right:170px;top:230px">{phone(hp, 330)}</div></div>''', v / 'strukasir-product.png', 1920, 1080)
    # Texture: pola tepi struk (latar slide, kemasan, stiker)
    for name, bgc, line, op in [('indigo', INDIGO, WHITE, .12), ('light', SLATE_50, INDIGO, .10)]:
        render(f'<div style="width:1080px;height:1080px;background:{bgc} {texture_css(line, op, 72)}"></div>',
               v / f'strukasir-texture-{name}.png', 1080, 1080)


def build_guide():
    """Satu lembar ringkas panduan merek (PNG) dari aset yang sudah dibuat."""
    def row(kind, label):
        cells = ''.join(f'''<div style="background:{VARIANT_BG[var]};border:1px solid {SLATE_200};border-radius:14px;height:200px;display:flex;align-items:center;justify-content:center">
            <img src="{img_uri(OUT / 'logo' / kind / f'strukasir-{kind}-{var}.png')}" style="max-width:80%;max-height:{60 if kind == 'simplified' else 130}px"></div>''' for var in VARIANTS)
        return f'<div style="font-size:20px;font-weight:700;color:{SLATE_500};text-transform:uppercase;letter-spacing:2px;margin:36px 0 14px">{label}</div><div style="display:grid;grid-template-columns:repeat(4,1fr);gap:16px">{cells}</div>'
    body = (f'<div style="padding:80px;width:1600px;background:#fff">{lockup_img("color", 64)}'
            f'<div style="font-size:48px;font-weight:800;color:{INK};margin-top:40px">Panduan merek</div>'
            f'<div style="font-size:24px;color:{SLATE_500};margin-top:8px">Berwarna · terbalik (latar indigo) · satu warna gelap · satu warna terang</div>'
            + row('primary', 'Primary — simbol + nama') + row('secondary', 'Secondary — bertumpuk')
            + row('simplified', 'Simplified — nama saja') + row('submark', 'Sub-mark — simbol struk')
            + f'<img src="{img_uri(OUT / "colors" / "strukasir-colors.png")}" style="width:100%;margin-top:48px;border-radius:14px">'
            + f'<img src="{img_uri(OUT / "typography" / "strukasir-typography.png")}" style="width:100%;margin-top:24px;border-radius:14px"></div>')
    render(body, OUT / 'strukasir-brand-guide.png', 1600, 3640)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--shots', type=Path, required=True, help='folder screenshot app (kasir-isi, laporan, hp)')
    args = ap.parse_args()
    build_logos()
    build_email_logo()
    build_colors()
    build_type()
    build_ads(args.shots)
    build_visuals(args.shots)
    build_guide()
    # Simpan screenshot sumber supaya iklan bisa dibuat ulang tanpa menjalankan tes app.
    (OUT / 'visuals' / 'source').mkdir(parents=True, exist_ok=True)
    for f in ['kasir-isi__tablet-landscape.png', 'laporan__tablet-landscape.png', 'kasir-isi__hp-portrait.png']:
        shutil.copy(args.shots / f, OUT / 'visuals' / 'source' / f)
    print('selesai:', OUT)


if __name__ == '__main__':
    main()
