// Generate STRUKASIR logo SVGs + Android/Flutter PNGs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';
import opentype from 'opentype.js';

const REPO = path.resolve(fileURLToPath(new URL('../..', import.meta.url)));
const C = {
  primary: '#3730A3', primaryOnDark: '#A5B4FC', accent: '#F59E0B',
  ink: '#0F172A', onInk: '#F8FAFC', white: '#FFFFFF', surfaceApp: '#F8FAFC',
};

// --- Plus Jakarta Sans ExtraBold → path (untuk huruf S di mark & wordmark) ---
const buf = fs.readFileSync(`${REPO}/app/assets/fonts/PlusJakartaSans-ExtraBold.ttf`);
const font = opentype.parse(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
const UPM = font.unitsPerEm;
const CAP = font.tables.os2.sCapHeight || UPM * 0.7;

/** Teks → path dengan tinggi huruf kapital `capHeight`; baseline di y = top + capHeight. */
function textPath(text, capHeight, { x = 0, top = 0, tracking = 0 } = {}) {
  const size = capHeight * UPM / CAP;
  let cx = x;
  const parts = [];
  for (const g of [...text].map((ch) => font.charToGlyph(ch))) {
    parts.push(g.getPath(cx, top + capHeight, size).toPathData(2));
    cx += g.advanceWidth * size / UPM + tracking * size;
  }
  cx -= tracking * size;
  const bb = font.charToGlyph(text[0]).getBoundingBox();
  return { d: parts.join(''), width: cx - x, size, leftBearing: bb.x1 * size / UPM };
}

// --- Geometri mark (viewBox 0 0 96 96) ---
// Struk: sudut atas tegas (radius 3), sisi bawah bergerigi 5 gigi.
const RECEIPT = 'M18 13a3 3 0 0 1 3-3h54a3 3 0 0 1 3 3v67l-6 6-6-6-6 6-6-6-6 6-6-6-6 6-6-6-6 6-6-6z';
// Huruf S (cap 38, baseline y=63) + titik amber di baseline, keduanya dipusatkan di struk.
const S_CAP = 38, S_TOP = 25, DOT_R = 6, GAP = 3;
const sProbe = font.charToGlyph('S').getBoundingBox();
const sScale = (S_CAP * UPM / CAP) / UPM;
const sInk = (sProbe.x2 - sProbe.x1) * sScale; // lebar tinta S
const groupW = sInk + GAP + DOT_R * 2;
const sX = 48 - groupW / 2 - sProbe.x1 * sScale;
const LETTER = textPath('S', S_CAP, { x: sX, top: S_TOP }).d;
const DOT = { cx: 48 - groupW / 2 + sInk + GAP + DOT_R, cy: S_TOP + S_CAP - DOT_R, r: DOT_R };

const markGroup = ({ body, letter, dot }) =>
  `<path d="${RECEIPT}" fill="${body}"/><path d="${LETTER}" fill="${letter}"/><circle cx="${DOT.cx.toFixed(2)}" cy="${DOT.cy}" r="${DOT.r}" fill="${dot}"/>`;

// Versi satu warna: struk dengan S & titik dilubangi (alpha), untuk ikon monokrom & cetak termal.
const monoGroup = (fill) =>
  `<defs><mask id="m"><rect width="96" height="96" fill="#fff"/><path d="${LETTER}" fill="#000"/><circle cx="${DOT.cx.toFixed(2)}" cy="${DOT.cy}" r="${DOT.r}" fill="#000"/></mask></defs>` +
  `<path d="${RECEIPT}" fill="${fill}" mask="url(#m)"/>`;

const svg = (w, h, inner, vb = `0 0 ${w} ${h}`) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${vb}">${inner}</svg>\n`;

const MARK = markGroup({ body: C.primary, letter: C.white, dot: C.accent });
const MARK_REV = markGroup({ body: C.white, letter: C.primary, dot: C.accent });
const SUBMARK = `<path d="${LETTER}" fill="${C.primary}"/><circle cx="${DOT.cx.toFixed(2)}" cy="${DOT.cy}" r="${DOT.r}" fill="${C.accent}"/>`;
const SUB_X = Math.floor(48 - groupW / 2) - 3, SUB_W = Math.ceil(groupW) + 6;

// --- Wordmark "STRUKASIR" ---
const WM = textPath('STRUKASIR', 40, { tracking: 0.03 });
const wmSvg = (fill) => svg(Math.ceil(WM.width), 40, `<path d="${WM.d}" fill="${fill}"/>`);

// Lockup: mark 96 + wordmark (cap 40, dipusatkan di y=48). Struk berakhir di x=78; wordmark mulai x=98.
const lockup = (markInner, wmFill) => {
  const w = Math.ceil(98 + WM.width + 4 - 14);
  return svg(w, 96, `${markInner}<g transform="translate(98 28)"><path d="${WM.d}" fill="${wmFill}"/></g>`, `14 0 ${w} 96`);
};

// Ikon app: kotak membulat indigo, struk putih.
const APP_ICON = `<rect width="96" height="96" rx="22" fill="${C.primary}"/>` +
  `<g transform="translate(48 48) scale(.74) translate(-48 -48)">${MARK_REV}</g>`;
// Adaptive foreground (108dp, zona aman lingkaran Ø66): struk putih.
const FG = `<g transform="translate(54 54) scale(.68) translate(-48 -48)">${MARK_REV}</g>`;
const MONO_FG = `<g transform="translate(54 54) scale(.68) translate(-48 -48)">${monoGroup('#FFFFFF')}</g>`;

// --- Tulis SVG sumber ---
const SRC = `${REPO}/docs/brand`;
fs.mkdirSync(SRC, { recursive: true });
const sources = {
  'strukasir-mark.svg': svg(96, 96, MARK),
  'strukasir-mark-reversed.svg': svg(96, 96, MARK_REV),
  'strukasir-mark-mono.svg': svg(96, 96, monoGroup(C.ink)),
  'strukasir-submark.svg': svg(SUB_W, 46, SUBMARK, `${SUB_X} 21 ${SUB_W} 46`),
  'strukasir-wordmark.svg': wmSvg(C.ink),
  'strukasir-wordmark-reversed.svg': wmSvg(C.onInk),
  'strukasir-lockup.svg': lockup(MARK, C.ink),
  'strukasir-lockup-reversed.svg': lockup(MARK_REV, C.onInk),
  'strukasir-app-icon.svg': svg(96, 96, APP_ICON),
};
for (const [f, s] of Object.entries(sources)) fs.writeFileSync(`${SRC}/${f}`, s);

// --- Raster ---
function png(svgText, size, out, bg) {
  const r = new Resvg(svgText, { fitTo: { mode: 'width', value: size }, background: bg });
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, r.render().asPng());
}

const A = `${REPO}/app/assets/brand`;
for (const [scale, dir] of [[1, ''], [2, '2.0x/'], [3, '3.0x/']]) {
  png(sources['strukasir-mark.svg'], 128 * scale, `${A}/${dir}mark.png`);
  png(sources['strukasir-mark-reversed.svg'], 128 * scale, `${A}/${dir}mark_reversed.png`);
}

const RES = `${REPO}/app/android/app/src/main/res`;
const dens = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };
for (const [d, k] of Object.entries(dens)) {
  png(sources['strukasir-app-icon.svg'], 48 * k, `${RES}/mipmap-${d}/ic_launcher.png`);
  png(svg(108, 108, FG), 108 * k, `${RES}/mipmap-${d}/ic_launcher_foreground.png`);
  png(svg(108, 108, MONO_FG), 108 * k, `${RES}/mipmap-${d}/ic_launcher_monochrome.png`);
  png(sources['strukasir-mark.svg'], 96 * k, `${RES}/drawable-${d}/launch_mark.png`);
}

// Play Store: ikon 512 (tanpa sudut membulat; Play yang memotong).
png(svg(96, 96, `<rect width="96" height="96" fill="${C.primary}"/><g transform="translate(48 48) scale(.74) translate(-48 -48)">${MARK_REV}</g>`), 512, `${SRC}/play-store-icon-512.png`);
// Pratinjau untuk dicek mata.
png(sources['strukasir-lockup.svg'], 1200, `${SRC}/preview-lockup.png`, C.surfaceApp);
console.log('ok', WM.width.toFixed(1));
