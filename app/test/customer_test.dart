import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/customers/customer_api.dart';
import 'package:berrybrew_pos/features/customers/customer_form.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/printing/receipt_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'menu_test.dart' show menuJson;
import 'receipt_format_test.dart' show order;

void main() {
  group('tampilan data pelanggan', () {
    test('no HP +62 ditampilkan dalam format lokal', () {
      expect(formatPhone('+6281234567890'), '0812-3456-7890');
      expect(formatPhone('+628123456789'), '0812-3456-789');
      expect(formatPhone('0812****7890'), '0812****7890');
      expect(formatPhone('+6512345678'), '+6512345678', reason: 'nomor luar negeri apa adanya');
      expect(formatPhone(null), '');
    });

    test('terakhir datang dalam bahasa sehari-hari', () {
      final now = DateTime(2026, 10, 9, 15);
      expect(sinceLabel(null, now: now), 'Belum pernah belanja');
      expect(sinceLabel(DateTime(2026, 10, 9, 8), now: now), 'Hari ini');
      expect(sinceLabel(DateTime(2026, 10, 8, 23), now: now), 'Kemarin');
      expect(sinceLabel(DateTime(2026, 9, 29), now: now), '10 hari lalu');
      expect(sinceLabel(DateTime(2026, 6, 1), now: now), '4 bulan lalu');
      expect(sinceLabel(DateTime(2024, 1, 1), now: now), '2 tahun lalu');
      expect(formatDate('1990-05-01'), '1 Mei 1990');
    });

    test('data kasir tanpa total belanja; owner lengkap', () {
      final cashier = Customer.fromJson({'id': 'c1', 'code': 'M0001', 'name': 'Andi', 'phone': '0812****7890', 'visits': 3});
      expect([cashier.totalSpent, cashier.average], [null, null]);
      final owner = Customer.fromJson({
        'id': 'c1', 'code': 'M0001', 'name': 'Andi', 'phone': '+6281234567890', 'visits': 4, 'total_spent': 100000,
        'birth_date': '1990-05-01', 'last_visit_at': '2026-10-01T03:00:00Z',
      });
      expect(owner.average, 25000);
      expect(owner.lastVisitAt!.isUtc, isFalse, reason: 'diubah ke waktu lokal');
    });
  });

  group('member di keranjang', () {
    const andi = CartCustomer(id: 'c1', code: 'M0001', name: 'Andi');

    test('pilih member mengisi nama yang masih kosong & ikut terkirim ke server', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cart = container.read(cartProvider.notifier);

      cart.setCustomer(andi);
      expect(container.read(cartProvider).customerLabel, 'Andi');
      expect(container.read(cartProvider).toJson(0)['customer_id'], 'c1');

      cart.clearCustomer();
      expect(container.read(cartProvider).customer, isNull);
      expect(container.read(cartProvider).customerLabel, '', reason: 'label = nama member ikut dilepas');
      expect(container.read(cartProvider).toJson(0)['customer_id'], isNull);
    });

    test('label yang sudah diisi (mis. nomor meja) tidak ditimpa', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cart = container.read(cartProvider.notifier);

      cart.setCustomerLabel('Meja 5');
      cart.setCustomer(andi);
      expect(container.read(cartProvider).customerLabel, 'Meja 5');
      cart.clearCustomer();
      expect(container.read(cartProvider).customerLabel, 'Meja 5');
    });

    test('open bill bermember dimuat lagi lengkap dengan membernya', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cartProvider.notifier).loadOrder({
        ...order(status: 'open'),
        'customer': {'id': 'c9', 'code': 'M0009', 'name': 'Siti', 'anonymized': false},
      }, Menu.fromJson(menuJson));
      final state = container.read(cartProvider);
      expect([state.customer?.id, state.customer?.code], ['c9', 'M0009']);
      expect(state.toJson(0)['customer_id'], 'c9');
    });
  });

  test('struk mencetak kode member (bukan no HP), kecuali datanya sudah dihapus', () {
    final withMember = customerReceipt({
      ...order(),
      'customer': {'id': 'c1', 'code': 'M0001', 'name': 'Andi', 'anonymized': false},
    }).join('\n');
    expect(withMember, contains('Member: M0001'));

    final anonymized = customerReceipt({
      ...order(),
      'customer': {'id': 'c1', 'code': 'M0001', 'name': 'Pelanggan dihapus', 'anonymized': true},
    }).join('\n');
    expect(anonymized, isNot(contains('Member:')));
    expect(customerReceipt(order()).join('\n'), isNot(contains('Member:')));
  });

  test('fitur pelanggan & no HP wajib dibaca dari menu', () {
    final old = Menu.fromJson(menuJson);
    expect([old.customersOn, old.customerPhoneRequired], [false, true], reason: 'server lama');
    final on = Menu.fromJson({...menuJson, 'features': {'customers': true}, 'customer_phone_required': false});
    expect([on.customersOn, on.customerPhoneRequired], [true, false]);
  });
}
