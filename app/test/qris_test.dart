import 'dart:convert';
import 'dart:typed_data';

import 'package:berrybrew_pos/features/cart/order_api.dart';
import 'package:berrybrew_pos/features/cart/payment_dialog.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/printing/receipt_format.dart';
import 'package:berrybrew_pos/features/printing/receipt_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'loyalty_test.dart' show loyaltyMenuJson;

/// Gambar mirip QR: kotak hitam-putih 25×25 modul dengan tepi putih, diperbesar [scale] kali.
Uint8List fakeQr(int scale, {bool jpg = false}) {
  const modules = 25, quiet = 4;
  final size = (modules + quiet * 2) * scale;
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < modules; y++) {
    for (var x = 0; x < modules; x++) {
      if ((x * 7 + y * 3) % 5 < 2) {
        img.fillRect(image,
            x1: (x + quiet) * scale, y1: (y + quiet) * scale, x2: (x + quiet + 1) * scale - 1, y2: (y + quiet + 1) * scale - 1,
            color: img.ColorRgb8(20, 20, 20));
      }
    }
  }
  return jpg ? img.encodeJpg(image) : img.encodePng(image);
}

void main() {
  test('gambar QRIS diproses jadi PNG hitam-putih, tepi dibuang, lebar ≤ 384', () {
    final big = processQris(fakeQr(40))!; // foto besar 1320 px
    expect(big.width, lessThanOrEqualTo(kQrisMaxWidth));
    final decoded = img.decodePng(big.png)!;
    expect(decoded.getPixel(0, 0).luminance < 128, isTrue, reason: 'tepi putih dibuang → mulai dari modul hitam');
    final small = processQris(fakeQr(3))!; // 99 px → diperbesar tajam
    expect(small.width, greaterThanOrEqualTo(120));
    expect(processQris(fakeQr(20, jpg: true)), isNotNull, reason: 'JPG juga diterima');
    expect(processQris(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('menu membawa QRIS, referensi dikirim, bill memuat baris QRIS', () {
    final menu = Menu.fromJson({...loyaltyMenuJson, 'qris': {'image': 'AAAA', 'print_on_bill': true}});
    expect([menu.qrisImage, menu.qrisOnBill], ['AAAA', true]);
    expect(Menu.fromJson(loyaltyMenuJson).qrisImage, isNull);
    expect(PaymentDraft(method: 'qris', amount: 20000, reference: ' 4821 ').toJson()['reference'], '4821');
    expect(PaymentDraft(method: 'qris', amount: 20000, reference: '').toJson().containsKey('reference'), isFalse);
    expect(qrisBillLines({'grand_total': 45000}).map((l) => l.text.trim()), containsAll(['Bayar dengan QRIS', 'Rp 45.000']));
  });

  testWidgets('bayar QRIS: wajib centang dana masuk; QRIS bisa ditunjukkan ke pembeli', (t) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    List<PaymentDraft>? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showDialog<List<PaymentDraft>>(
              context: context,
              builder: (_) => PaymentDialog(
                total: 20000, splitEnabled: false, number: 'T1-0001',
                qrisImage: base64Encode(processQris(fakeQr(10))!.png), shopName: 'Kedai Uji',
              ),
            ),
            child: const Text('bayar'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('bayar'));
    await t.pumpAndSettle();
    await t.tap(find.text('QRIS'));
    await t.pumpAndSettle();

    final confirm = find.widgetWithText(FilledButton, 'Konfirmasi diterima');
    expect(t.widget<FilledButton>(confirm).onPressed, isNull, reason: 'belum dicentang');
    expect(find.text('Centang dulu bahwa dana QRIS sudah masuk'), findsOneWidget);

    await t.tap(find.text('Tampilkan QRIS ke pembeli'));
    await t.pumpAndSettle();
    expect(find.text('Scan untuk membayar'), findsOneWidget);
    expect(find.text('Rp 20.000'), findsWidgets);
    await t.tap(find.text('Selesai, kembali'));
    await t.pumpAndSettle();

    await t.tap(find.text('Dana Rp 20.000 sudah masuk di aplikasi merchant'));
    await t.enterText(find.widgetWithText(TextField, 'No. referensi (opsional)'), '4821');
    await t.pumpAndSettle();
    await t.tap(confirm);
    await t.pumpAndSettle();
    expect(result!.single.toJson(), containsPair('reference', '4821'));
  });
}
