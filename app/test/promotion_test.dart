import 'package:berrybrew_pos/core/shop_clock.dart';
import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/cart/pricing.dart';
import 'package:berrybrew_pos/features/customers/member_tier.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/menu/modifier_selection.dart';
import 'package:berrybrew_pos/features/printing/receipt_format.dart';
import 'package:berrybrew_pos/features/promotions/promotion_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loyalty_test.dart' show loyaltyMenuJson;
import 'receipt_format_test.dart' show order;

/// Rabu 14 Okt 2026.
DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 14, h, m);

void main() {
  final happyHour = {
    'id': 'p-hh', 'name': 'Happy Hour', 'type': 'percent', 'value': 2000, 'scope': 'categories', 'target_ids': ['kopi'],
    'days': [3], 'start_time': '14:00', 'end_time': '17:00',
  };
  Menu menuWith(List<Map<String, dynamic>> promos) => Menu.fromJson({...loyaltyMenuJson, 'promotions': promos});
  final menu = menuWith([happyHour]);
  final latte = menu.product('latte')!;
  final roti = menu.product('roti')!;

  (ProviderContainer, CartController) cart(List<(MenuProduct, int)> items) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(cartProvider.notifier);
    for (final (p, qty) in items) {
      n.add(ModifierSelection(p, const []));
      n.setQty(c.read(cartProvider).lines.last.id, qty);
    }
    return (c, n);
  }

  group('jadwal promo = PromotionService::runsAt', () {
    final p = menu.promotions.single;
    test('hari & jam (jam selesai tidak termasuk)', () {
      expect([p.runsAt(at(14)), p.runsAt(at(16, 59)), p.runsAt(at(17)), p.runsAt(at(13, 59))], [true, true, false, false]);
      expect(p.runsAt(DateTime(2026, 10, 15, 15)), isFalse, reason: 'Kamis');
    });
    test('melewati tengah malam & rentang tanggal', () {
      const night = Promotion(id: 'n', name: 'Malam', type: 'percent', value: 1000, times: [(start: '22:00', end: '02:00')]);
      expect([night.runsAt(at(23)), night.runsAt(at(1, 59)), night.runsAt(at(2)), night.runsAt(at(12))], [true, true, false, false]);
      const dated = Promotion(id: 'd', name: 'Okt', type: 'percent', value: 1000, startsOn: '2026-10-15', endsOn: '2026-10-31');
      expect([dated.runsAt(at(10)), dated.runsAt(DateTime(2026, 10, 31, 23)), dated.runsAt(DateTime(2026, 11, 1))], [false, true, false]);
    });
  });

  test('beberapa rentang jam (happy hour siang & malam)', () {
    final p = Promotion.fromJson({
      'id': 'w', 'name': 'HH', 'type': 'percent', 'value': 2000,
      'times': [{'start': '12:00', 'end': '14:00'}, {'start': '19:00', 'end': '21:00'}],
    });
    expect([p.runsAt(at(12, 30)), p.runsAt(at(15)), p.runsAt(at(20, 59)), p.runsAt(at(21))], [true, false, true, false]);
    expect(p.schedule, 'Setiap hari · 12:00–14:00, 19:00–21:00');
  });

  test('harga spesial, beli banyak, paket bundling (angka sama dengan PromotionTest server)', () {
    final m = menuWith([
      {'id': 'b', 'name': 'Borong roti', 'type': 'min_qty', 'buy_qty': 3, 'value': 1000, 'scope': 'all'},
      {'id': 'l', 'name': 'Latte 15rb', 'type': 'price', 'value': 15000, 'scope': 'products', 'target_ids': ['latte']},
    ]);
    var (c, _) = cart([(latte, 2), (roti, 3)]);
    expect(priceCart(c.read(cartProvider), m, at: at(9)).lineDiscounts, [10000, 3000]);
    (c, _) = cart([(roti, 2)]);
    expect(priceCart(c.read(cartProvider), m, at: at(9)).lineDiscounts, [0]);

    final paket = menuWith([
      {'id': 'p', 'name': 'Paket Sarapan', 'type': 'bundle', 'value': 25000, 'scope': 'all', 'bundle_items': [
        {'product_id': 'latte', 'qty': 1}, {'product_id': 'roti', 'qty': 1},
      ]},
    ]);
    (c, _) = cart([(latte, 2), (roti, 1)]);
    var s = c.read(cartProvider);
    final r = priceCart(s, paket, at: at(9));
    expect([r.lineDiscounts, r.grandTotal], [[3333, 1667], 45000]);
    expect(lineBenefit(s, paket, s.lines.last, at(9))?.label, 'Paket Sarapan');
    (c, _) = cart([(latte, 2)]);
    expect(priceCart(c.read(cartProvider), paket, at: at(9)).lineDiscounts, [0]);
    (c, _) = cart([(roti, 2), (latte, 2)]); // 2 paket
    s = c.read(cartProvider);
    expect(priceCart(s, paket, at: at(9)).lineDiscounts, [3334, 6666]);
  });

  test('jam kedai: zona waktu kedai & jam open bill dibuat', () {
    // 16:55 WIB = 09:55 UTC; menu WIB (+420 menit).
    final created = DateTime.utc(2026, 10, 14, 9, 55);
    expect(ShopClock.wall(420, created), DateTime.utc(2026, 10, 14, 16, 55));
    final m = Menu.fromJson({...loyaltyMenuJson, 'promotions': [happyHour], 'clock': {'now': '2026-10-14T10:20:00+00:00', 'utc_offset': 420}});
    expect(m.utcOffset, 420);
    final (c, n) = cart([(latte, 2)]);
    n.loadOrder({
      'id': 'o1', 'number': 'T1-0001', 'created_at': created.toIso8601String(), 'customer_label': 'A',
      'items': [{'id': 'i1', 'product_id': 'latte', 'name': 'Latte', 'unit_price': 20000, 'qty': 2, 'modifiers': [], 'discount': null}],
    }, m);
    final s = c.read(cartProvider);
    expect(promoTime(s, m), DateTime.utc(2026, 10, 14, 16, 55));
    expect(priceCart(s, m).lineDiscounts, [8000], reason: 'open bill dibuat saat happy hour tetap dapat promo');
  });

  test('potongan per jenis promo', () {
    const percent = Promotion(id: 'a', name: 'A', type: 'percent', value: 2000);
    const amount = Promotion(id: 'b', name: 'B', type: 'amount', value: 2000);
    const bogo = Promotion(id: 'c', name: 'C', type: 'bogo', buyQty: 2, freeQty: 1);
    int d(Promotion p, {int unit = 25000, int qty = 5, int base = 20000}) =>
        p.discountFor(productId: 'latte', categoryId: 'kopi', unitPrice: unit, qty: qty, basePrice: base);
    expect(d(percent), 25000); // 20% × 125.000
    expect(d(amount), 10000); // 2.000 × 5
    expect(d(amount, unit: 1000, qty: 1), 1000, reason: 'maks. harga baris');
    expect(d(bogo), 20000); // ⌊5/3⌋ = 1 gratis × harga dasar
    expect(d(bogo, qty: 6), 40000);
    expect(d(bogo, qty: 2), 0);
  });

  test('promo hanya saat jadwal & kategorinya; label nama promo', () {
    final (c, _) = cart([(latte, 2), (roti, 1)]);
    final state = c.read(cartProvider);
    expect(priceCart(state, menu, at: at(15)).lineDiscounts, [8000, 0]);
    expect(lineBenefit(state, menu, state.lines.first, at(15))?.label, 'Happy Hour');
    expect(priceCart(state, menu, at: at(18)).grandTotal, 50000);
  });

  test('terbesar antara promo & tingkat member; diskon manual tidak disentuh', () {
    final (c, n) = cart([(latte, 1), (roti, 1)]);
    n.setLineDiscount(c.read(cartProvider).lines.last.id, const Discount.amount(1000));
    n.setCustomer(const CartCustomer(id: 'c', code: 'M1', name: 'A', tier: MemberTier(id: 't', name: 'Gold', discountBp: 1500)));
    final m = menuWith([{...happyHour, 'value': 1000}]); // promo 10% < Gold 15%
    var s = c.read(cartProvider);
    expect(priceCart(s, m, at: at(15)).lineDiscounts, [3000, 1000]);
    expect(lineBenefit(s, m, s.lines.first, at(15))?.label, 'Diskon member');

    final big = menuWith([{...happyHour, 'value': 5000}]); // promo 50% > Gold
    s = c.read(cartProvider);
    expect(priceCart(s, big, at: at(15)).lineDiscounts.first, 10000);
    expect(lineBenefit(s, big, s.lines.first, at(15))?.label, 'Happy Hour');
  });

  test('promo yang sama besar: yang pertama menurut nama (sama dengan server)', () {
    final m = menuWith([
      {'id': 'a', 'name': 'A promo', 'type': 'amount', 'value': 2000, 'scope': 'all'},
      {'id': 'b', 'name': 'B promo', 'type': 'amount', 'value': 2000, 'scope': 'all'},
    ]);
    final (c, _) = cart([(roti, 1)]);
    expect(lineBenefit(c.read(cartProvider), m, c.read(cartProvider).lines.first, at(9))?.label, 'A promo');
  });

  test('voucher: % dengan batas, minimal belanja, menggantikan diskon order manual', () {
    const v = VoucherTerms(code: 'HEMAT10', type: 'percent', value: 1000, maxDiscount: 5000, minSpend: 30000);
    expect([v.discountFor(20000), v.discountFor(40000), v.discountFor(80000)], [0, 4000, 5000]);

    final (c, n) = cart([(roti, 8)]);
    n.setOrderDiscount(const Discount.amount(1000));
    n.setVoucher(v);
    final s = c.read(cartProvider);
    expect(s.orderDiscount, isNull);
    expect(priceCart(s, menu, at: at(9)).grandTotal, 75000);
    expect(s.toJson(0)['voucher_code'], 'HEMAT10');
    n.clearVoucher();
    expect(c.read(cartProvider).toJson(0).containsKey('voucher_code'), isFalse);
  });

  test('struk: nama promo di item & kode voucher di diskon order', () {
    final paid = order();
    final items = (paid['items'] as List).cast<Map<String, dynamic>>();
    final text = customerReceipt({
      ...paid,
      'items': [{...items.first, 'discount_total': 3000, 'promo': 'Happy Hour'}, items.last],
      'voucher': {'code': 'HEMAT10', 'discount': 5000},
    }).join('\n');
    expect(text, contains('Happy Hour'));
    expect(text, contains('Voucher HEMAT10'));
  });
}
