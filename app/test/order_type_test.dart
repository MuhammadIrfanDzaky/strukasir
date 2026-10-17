import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/menu/modifier_selection.dart';
import 'package:berrybrew_pos/features/printing/receipt_format.dart';
import 'package:berrybrew_pos/features/printing/stations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loyalty_test.dart' show loyaltyMenuJson;

void main() {
  Menu menu({bool on = true, String def = 'takeaway'}) => Menu.fromJson({
        ...loyaltyMenuJson,
        'pricing': {'service_bp': 1000, 'tax_bp': 0, 'rounding_unit': 0, 'cashier_discount_limit_bp': 0},
        'order_types': {'enabled': on, 'default': def},
      });

  (ProviderContainer, CartController) cartWithLatte(Menu m) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(cartProvider.notifier);
    n.add(ModifierSelection(m.product('latte')!, const []));
    return (c, n);
  }

  test('service charge hanya dine-in (sama dengan OrderService); fitur mati = seperti biasa', () {
    final m = menu();
    final (c, n) = cartWithLatte(m);
    expect(c.read(cartProvider).typeIn(m), 'takeaway', reason: 'jenis awal kedai');
    expect(priceCart(c.read(cartProvider), m).grandTotal, 20000);
    n.setOrderType('dine_in');
    n.setTableLabel('12');
    expect(priceCart(c.read(cartProvider), m).serviceTotal, 2000);
    expect(c.read(cartProvider).toJson(22000), containsPair('table_label', '12'));
    expect(c.read(cartProvider).toJson(22000), containsPair('order_type', 'dine_in'));

    final off = menu(on: false);
    expect(c.read(cartProvider).typeIn(off), isNull);
    expect(priceCart(c.read(cartProvider), off).serviceTotal, 2000);
    expect(priceCart(c.read(cartProvider), menu(def: 'dine_in')).serviceTotal, 2000);
  });

  test('order baru: jenis kosong = jenis awal server; open bill membawa jenis & meja', () {
    final m = menu(def: 'dine_in');
    final (c, n) = cartWithLatte(m);
    expect(c.read(cartProvider).toJson(0).containsKey('order_type'), isFalse);
    expect(c.read(cartProvider).typeIn(m), 'dine_in');
    n.loadOrder({
      'id': 'o1', 'number': 'T1-0001', 'created_at': '2026-10-17T03:00:00Z', 'customer_label': 'Budi',
      'order_type': 'takeaway', 'table_label': null,
      'items': [{'id': 'i1', 'product_id': 'latte', 'name': 'Latte', 'unit_price': 20000, 'qty': 1, 'modifiers': [], 'discount': null}],
    }, m);
    expect(c.read(cartProvider).typeIn(m), 'takeaway');
    expect(priceCart(c.read(cartProvider), m).serviceTotal, 0);
  });

  test('struk, tiket dapur & label daftar menyebut jenis pesanan', () {
    final dine = {'order_type': 'dine_in', 'table_label': '5', 'customer_label': 'Budi'};
    expect(orderTypeLine(dine), 'DINE-IN · Meja 5');
    expect(orderTypeLine({'order_type': 'takeaway'}), 'TAKEAWAY');
    expect(orderTypeLine({'order_type': null}), isNull);
    expect(orderLabel(dine), 'Meja 5 · Budi');
    final ticket = kitchenTicket(station: 'Bar', number: 'T1-0001', label: 'Budi', items: const [], at: DateTime(2026, 10, 17, 9), orderType: 'DINE-IN · Meja 5');
    expect(ticket.map((l) => l.text), contains('DINE-IN · Meja 5'));
  });
}
