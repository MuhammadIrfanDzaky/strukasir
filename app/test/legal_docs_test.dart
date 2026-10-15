import 'dart:io';

import 'package:berrybrew_pos/core/theme/theme.dart';
import 'package:berrybrew_pos/features/legal/legal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('salinan dokumen legal di app sama dengan docs/legal', () {
    for (final name in ['syarat-ketentuan.md', 'kebijakan-privasi.md']) {
      final asset = File('assets/legal/$name').readAsStringSync().replaceAll('\r\n', '\n');
      final doc = File('../docs/legal/$name').readAsStringSync().replaceAll('\r\n', '\n');
      expect(asset, doc, reason: 'Salin ulang docs/legal/$name ke app/assets/legal/ setelah mengubah dokumen.');
    }
  });

  for (final (label, size) in [('hp', const Size(360, 780)), ('tablet', const Size(1280, 800))]) {
    testWidgets('halaman syarat & privasi tampil tanpa overflow ($label)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final texts = {for (final d in LegalDoc.values) d: File(d.asset).readAsStringSync()};
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: LegalScreen(texts: texts)));
      await tester.pumpAndSettle();
      expect(find.text('Syarat & Ketentuan Layanan Strukasir'), findsOneWidget);
      expect(find.textContaining('Pengembalian dana'), findsWidgets);

      await tester.tap(find.text('Kebijakan Privasi'));
      await tester.pumpAndSettle();
      expect(find.text('Kebijakan Privasi Strukasir'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
