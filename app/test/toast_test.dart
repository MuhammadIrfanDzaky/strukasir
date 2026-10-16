import 'package:berrybrew_pos/core/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toast muncul di kanan atas lalu hilang sendiri', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppToast.of(context).showSnackBar(const SnackBar(content: Text('Kasir ditambahkan'))),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 300));
    final box = tester.getRect(find.text('Kasir ditambahkan'));
    expect(box.top, lessThan(100), reason: 'di atas');
    expect(box.right, greaterThan(1280 - 200), reason: 'di kanan');

    // Toast baru menggantikan yang lama.
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kasir ditambahkan'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Kasir ditambahkan'), findsNothing);
  });
}
