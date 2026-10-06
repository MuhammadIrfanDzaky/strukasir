// Regresi: mengetik nama pelanggan / meja. Dulu keyboard muncul lalu langsung tertutup, karena
// tinggi layar mengecil → panel keranjang berganti susunan → kolom kehilangan fokus.
import 'package:berrybrew_pos/core/theme/theme.dart';
import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/menu/menu_controller.dart';
import 'package:berrybrew_pos/features/menu/modifier_selection.dart';
import 'package:berrybrew_pos/features/printing/printer_service.dart';
import 'package:berrybrew_pos/features/session/session_controller.dart';
import 'package:berrybrew_pos/features/shift/shift_controller.dart';
import 'package:berrybrew_pos/home_shell.dart';
import 'package:berrybrew_pos/main.dart' show appBuilder;
import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'responsive_test.dart' show FakeMenu, FakePrinter, FakeSession, FakeShift, bigMenu, loggedIn;

Finder get labelField => find.widgetWithText(TextField, 'Nama pelanggan / meja *');

bool labelFocused(WidgetTester t) => t.widget<TextField>(labelField).focusNode!.hasFocus;

Future<void> pumpPos(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);

  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith(() => FakeSession(loggedIn)),
    menuProvider.overrideWith(FakeMenu.new),
    shiftProvider.overrideWith(FakeShift.new),
    printerProvider.overrideWith(FakePrinter.new),
  ]);
  addTearDown(container.dispose);
  await container.read(sessionProvider.future);
  await container.read(menuProvider.future);
  final cart = container.read(cartProvider.notifier);
  for (final p in bigMenu.products.where((p) => p.sellable && p.modifierGroupIds.isEmpty).take(3)) {
    cart.add(ModifierSelection(p, const []));
  }

  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: appBuilder,
      home: HomeShell(session: loggedIn),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Ketuk kolom nama, lalu "keyboard" muncul (inset bawah) → kolom harus tetap fokus & bisa diketik.
Future<void> typeWithKeyboard(WidgetTester t, double keyboard) async {
  await t.tap(labelField);
  await t.pump();
  expect(labelFocused(t), isTrue);

  t.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(t.view.resetViewInsets);
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }

  expect(labelFocused(t), isTrue, reason: 'keyboard tidak boleh langsung tertutup');
  await t.enterText(labelField, 'Wahyu');
  await t.pump();
  expect(find.text('Wahyu'), findsOneWidget);
}

void main() {
  testWidgets('tablet landscape: kolom nama tetap fokus saat keyboard muncul', (t) async {
    await pumpPos(t, const Size(1600, 900));
    await typeWithKeyboard(t, 420);
    expect(t.takeException(), isNull);
  });

  testWidgets('tablet portrait: kolom nama tetap fokus saat keyboard muncul', (t) async {
    await pumpPos(t, const Size(800, 1280));
    await typeWithKeyboard(t, 520);
    expect(t.takeException(), isNull);
  });

  testWidgets('HP: halaman pesanan, kolom nama tetap fokus saat keyboard muncul', (t) async {
    await pumpPos(t, const Size(390, 844));
    await t.tap(find.text('Lihat pesanan'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await typeWithKeyboard(t, 330);
    expect(t.takeException(), isNull);
  });

  testWidgets('nama pelanggan wajib sebelum Cek pesanan / Open Bill / Bayar', (t) async {
    await pumpPos(t, const Size(1280, 800));
    await t.tap(find.text('Cek pesanan'));
    await t.pump();
    expect(find.text('Isi nama pelanggan / meja dulu'), findsOneWidget);
    expect(labelFocused(t), isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
