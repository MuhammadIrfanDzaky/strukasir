import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/menu/modifier_selection.dart';
import 'package:berrybrew_pos/features/printing/stations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loyalty_test.dart' show loyaltyMenuJson;
import 'receipt_format_test.dart' show order;

void main() {
  final menu = Menu.fromJson(loyaltyMenuJson);
  final latte = menu.product('latte')!;
  final roti = menu.product('roti')!;
  final shot = menu.modifierGroups.first.modifiers.first;

  test('item yang belum dikirim: semua di order baru, lalu hanya tambahan', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final cart = c.read(cartProvider.notifier);
    final s = ModifierSelection(latte, menu.groupsFor(latte))..toggle(menu.modifierGroups.first, shot);
    cart.add(s);
    cart.add(ModifierSelection(roti, const []));
    cart.setNote(c.read(cartProvider).lines.first.id, 'es dipisah');

    var pending = pendingTicketItems(c.read(cartProvider));
    expect(pending.map((i) => '${i.qty}x ${i.name}'), ['1x Latte', '1x Roti']);
    expect([pending.first.options, pending.first.note, pending.first.categoryId], ['Extra shot', 'es dipisah', 'kopi']);

    cart.markTicketed();
    expect(pendingTicketItems(c.read(cartProvider)), isEmpty);

    cart.setQty(c.read(cartProvider).lines.first.id, 3); // tambah 2 latte
    cart.add(ModifierSelection(roti, const [])); // roti jadi 2 (baris sama)
    pending = pendingTicketItems(c.read(cartProvider));
    expect(pending.map((i) => '${i.qty}x ${i.name}'), ['2x Latte', '1x Roti']);
  });

  test('open bill dimuat ulang: item lama dianggap sudah dicetak', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(cartProvider.notifier).loadOrder({
      ...order(status: 'open'),
      'items': [
        {'id': 'i1', 'product_id': 'latte', 'name': 'Latte', 'unit_price': 20000, 'modifiers_total': 0, 'qty': 2,
          'note': null, 'discount': null, 'discount_total': 0, 'line_total': 40000, 'modifiers': []},
      ],
    }, menu);
    expect(pendingTicketItems(c.read(cartProvider)), isEmpty);
    c.read(cartProvider.notifier).setQty('i1', 3);
    expect(pendingTicketItems(c.read(cartProvider)).single.qty, 1);
  });

  test('stasiun hanya mengambil kategorinya; tiket tanpa harga', () {
    const bar = TicketStation(name: 'Bar', categoryIds: ['kopi']);
    expect([bar.takes('kopi'), bar.takes('makan'), const TicketStation(name: 'Semua').takes('makan')], [true, false, true]);

    final text = kitchenTicket(
      station: 'Bar',
      number: 'T1-0042',
      label: 'Meja 4 / Andi',
      items: const [TicketItem(qty: 2, name: 'Kopi Susu Aren', categoryId: 'kopi', options: 'Cold, Extra shot x2', note: 'less sugar')],
      at: DateTime(2026, 10, 10, 9, 5),
      addition: true,
    ).map((l) => l.text).join('\n');
    for (final part in ['BAR', '*** TAMBAHAN ***', 'T1-0042', '09:05', 'Meja 4 / Andi', '2x Kopi Susu Aren', 'Cold, Extra shot x2', '* less sugar']) {
      expect(text, contains(part));
    }
    expect(text, isNot(contains('Rp')));
    expect(text, isNot(contains('×')), reason: 'huruf × tidak ada di semua printer thermal');
  });

  test('cetak ulang dari order server', () {
    final items = orderTicketItems(order(), (id) => id == 'p1' ? 'kopi' : 'lain');
    expect(items.map((i) => '${i.qty}x ${i.name}').first, '1x Americano');
    expect(items.first.options, 'Cold');
    expect(items.last.note, 'es dipisah ya kak, gula sedikit');
  });

  test('stasiun tersimpan sebagai JSON', () {
    const s = TicketStation(name: 'Dapur', printerMac: 'AA:BB', printerName: 'Printer dapur', categoryIds: ['makan'], copies: 2);
    final back = TicketStation.fromJson(s.toJson());
    expect([back.name, back.printerMac, back.printerName, back.categoryIds, back.copies], ['Dapur', 'AA:BB', 'Printer dapur', ['makan'], 2]);
  });
}
