/// Mengubah gambar logo apa pun (foto/PNG/JPG) jadi logo struk thermal: hitam-putih, lebar
/// ≤ 384 titik (kertas 58 mm), tanpa tepi kosong. Fungsi murni → bisa dijalankan di isolate & diuji.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int kLogoMaxWidth = 384;
const int kLogoMaxHeight = 400;

/// Lebar logo di kertas (titik). Sedikit lebih kecil dari lebar penuh supaya ada margin.
const int kLogoTargetWidth = 320;

class LogoOptions {
  const LogoOptions({this.invert, this.threshold});

  /// Balik warna. Null = otomatis (dibalik bila latar logo gelap, mis. logo emas di atas hitam).
  final bool? invert;

  /// Batas gelap/terang untuk hitam-putih (0–255). Null = otomatis (Otsu) dari isi gambar,
  /// sehingga bagian logo yang warnanya lebih redup tidak ikut hilang.
  final int? threshold;
}

class ProcessedLogo {
  const ProcessedLogo(this.png,
      {required this.inverted, required this.threshold, required this.width, required this.height});

  final Uint8List png;
  final bool inverted;
  final int threshold;
  final int width;
  final int height;
}

/// Null bila file bukan gambar yang bisa dibaca.
ProcessedLogo? processLogo((Uint8List, LogoOptions) input) {
  final (bytes, options) = input;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // Latar transparan → putih.
  var image = img.Image(width: decoded.width, height: decoded.height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  image = img.compositeImage(image, decoded);
  image = img.grayscale(image);

  final invert = options.invert ?? _darkBackground(image);
  if (invert) image = img.invert(image);

  // Buang tepi kosong (putih) supaya logo tercetak sebesar mungkin.
  final trimmed = img.trim(image, mode: img.TrimMode.topLeftColor);
  if (trimmed.width >= 8 && trimmed.height >= 8) image = trimmed;

  // Perkecil: lebar ≤ kLogoTargetWidth, tinggi ≤ kLogoMaxHeight.
  if (image.width > kLogoTargetWidth) image = img.copyResize(image, width: kLogoTargetWidth, interpolation: img.Interpolation.average);
  if (image.height > kLogoMaxHeight) image = img.copyResize(image, height: kLogoMaxHeight, interpolation: img.Interpolation.average);
  // Gambar terlalu kecil diperbesar sedikit supaya terbaca di struk.
  if (image.width < 96) image = img.copyResize(image, width: 96);

  // Hitam-putih murni: printer thermal hanya mencetak titik hitam.
  final threshold = options.threshold ?? _otsu(image);
  final out = img.Image(width: image.width, height: image.height, numChannels: 1);
  for (final p in image) {
    final v = p.luminance < threshold ? 0 : 255;
    out.setPixelRgb(p.x, p.y, v, v, v);
  }
  return ProcessedLogo(img.encodePng(out, level: 9),
      inverted: invert, threshold: threshold, width: out.width, height: out.height);
}

/// Latar dianggap gelap bila rata-rata kecerahan piksel di tepi gambar < 50%.
bool _darkBackground(img.Image image) {
  var sum = 0.0;
  var n = 0;
  void add(int x, int y) {
    sum += image.getPixel(x, y).luminanceNormalized;
    n++;
  }

  for (var x = 0; x < image.width; x += 2) {
    add(x, 0);
    add(x, image.height - 1);
  }
  for (var y = 0; y < image.height; y += 2) {
    add(0, y);
    add(image.width - 1, y);
  }
  return n > 0 && sum / n < 0.5;
}

/// Batas hitam-putih otomatis (metode Otsu): memisahkan dua kelompok kecerahan (latar vs logo)
/// dengan selisih terbesar. Dibatasi 64–224 supaya tidak jadi hitam/putih total.
int _otsu(img.Image image) {
  final hist = List<int>.filled(256, 0);
  for (final p in image) {
    hist[p.luminance.toInt().clamp(0, 255)]++;
  }
  final total = image.width * image.height;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, threshold = 128;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sumAll - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t + 1;
    }
  }
  return threshold.clamp(64, 224);
}
