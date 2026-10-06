import 'dart:io';
import 'dart:typed_data';

import 'package:berrybrew_pos/features/printing/receipt_logo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Logo emas di atas hitam (seperti logo BerryBrew): lingkaran terang di tengah latar gelap.
img.Image darkLogo({int w = 900, int h = 600}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(10, 10, 10));
  img.fillCircle(image, x: w ~/ 2, y: h ~/ 2, radius: h ~/ 4, color: img.ColorRgb8(230, 170, 60));
  return image;
}

void main() {
  test('logo latar gelap otomatis dibalik, hitam-putih, dan muat kertas 58 mm', () {
    final result = processLogo((img.encodePng(darkLogo()), const LogoOptions()))!;
    final out = img.decodePng(result.png)!;

    expect(result.inverted, isTrue);
    expect(out.width, lessThanOrEqualTo(kLogoMaxWidth));
    expect(out.height, lessThanOrEqualTo(kLogoMaxHeight));
    // Hanya hitam & putih; logo (lingkaran) jadi hitam di atas kertas putih.
    final values = {for (final p in out) p.r.toInt()};
    expect(values.difference({0, 255}), isEmpty);
    expect(out.getPixel(out.width ~/ 2, out.height ~/ 2).r, 0);
    // Tepi kosong dipotong: logo memenuhi gambar.
    expect(out.width, closeTo(out.height, 4));
  });

  test('logo latar terang tidak dibalik; bisa dipaksa balik', () {
    final light = img.Image(width: 400, height: 200);
    img.fill(light, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(light, x1: 100, y1: 50, x2: 300, y2: 150, color: img.ColorRgb8(0, 0, 0));

    expect(processLogo((img.encodePng(light), const LogoOptions()))!.inverted, isFalse);
    expect(processLogo((img.encodePng(light), const LogoOptions(invert: true)))!.inverted, isTrue);
  });

  test('bukan gambar → null', () {
    expect(processLogo((Uint8List.fromList(List.filled(64, 7)), const LogoOptions())), isNull);
  });

  // Dijalankan manual: LOGO_IN=<gambar> LOGO_OUT=<png> flutter test test/receipt_logo_test.dart
  final input = Platform.environment['LOGO_IN'];
  test('proses gambar nyata', () {
    final result = processLogo((File(input!).readAsBytesSync(), const LogoOptions()))!;
    File(Platform.environment['LOGO_OUT']!).writeAsBytesSync(result.png);
    // ignore: avoid_print
    print('logo ${result.width}x${result.height}, ${result.png.length} byte, dibalik: ${result.inverted}');
  }, skip: input == null);
}
