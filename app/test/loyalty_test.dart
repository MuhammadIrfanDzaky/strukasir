import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/cart/pricing.dart';
import 'package:berrybrew_pos/features/loyalty/loyalty_models.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/menu/modifier_selection.dart';
import 'package:berrybrew_pos/features/printing/receipt_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'receipt_format_test.dart' show order;

/// Menu kecil: Latte (Kopi, Rp20.000, bisa extra shot) & Roti (Makanan, Rp10.000) + program BerryCard.
final loyaltyMenuJson = <String, dynamic>{
  'version': 'v',
  'pricing': {'service_bp': 0, 'tax_bp': 0, 'rounding_unit': 0, 'cashier_discount_limit_bp': 1000},
  'features': {'modifiers': true, 'discounts': true, 'customers': true, 'loyalty': true},
  'categories': [
    {'id': 'kopi', 'name': 'Kopi', 'sort': 0, 'active': true},
    {'id': 'makan', 'name': 'Makanan', 'sort': 1, 'active': true},
  ],
  'products': [
    {'id': 'latte', 'category_id': 'kopi', 'name': 'Latte', 'price': 20000, 'active': true, 'sold_out': false, 'sort': 0,
      'modifier_group_ids': ['g']},
    {'id': 'roti', 'category_id': 'makan', 'name': 'Roti', 'price': 10000, 'active': true, 'sold_out': false, 'sort': 1,
      'modifier_group_ids': []},
  ],
  'modifier_groups': [
    {'id': 'g', 'name': 'Tambahan', 'min_select': 0, 'max_select': 1, 'sort': 0, 'modifiers': [
      {'id': 'shot', 'name': 'Extra shot', 'price_delta': 5000, 'active': true, 'sort': 0},
    ]},
  ],
  'loyalty': {
    'active': true, 'name': 'BerryCard', 'unit': 'stempel', 'earn_mode': 'per_item', 'category_ids': ['kopi'],
    'rewards': [
      {'id': 'r-amount', 'name': 'Potongan 5rb', 'cost': 2, 'type': 'amount', 'value': 5000},
      {'id': 'r-free', 'name': 'Gratis Latte', 'cost': 3, 'type': 'free_product', 'product_id': 'latte', 'value': 0},
      {'id': 'r-pct', 'name': 'Diskon 10%', 'cost': 5, 'type': 'percent', 'value': 1000},
    ],
  },
};

Menu menuWith([Map<String, dynamic>? loyalty]) =>
    Menu.fromJson({...loyaltyMenuJson, if (loyalty != null) 'loyalty': {...loyaltyMenuJson['loyalty'] as Map<String, dynamic>, ...loyalty}});

void main() {
  final menu = menuWith();
  final latte = menu.product('latte')!;
  final roti = menu.product('roti')!;
  final shot = menu.modifierGroups.first.modifiers.first;
  LoyaltyReward reward(String id) => menu.loyalty!.rewards.firstWhere((r) => r.id == id);
  const andi = CartCustomer(id: 'c1', code: 'M0001', name: 'Andi', balance: 9);

  (ProviderContainer, CartController) cartWith(List<(MenuProduct, List<MenuModifier>, int)> items) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final cart = container.read(cartProvider.notifier);
    for (final (p, mods, qty) in items) {
      final s = ModifierSelection(p, menu.groupsFor(p));
      for (final m in mods) {
        s.toggle(menu.modifierGroups.first, m);
      }
      cart.add(s);
      final line = container.read(cartProvider).lines.last;
      cart.setQty(line.id, qty);
    }
    cart.setCustomer(andi);
    return (container, cart);
  }

  test('program & hadiah dibaca dari menu', () {
    final p = menu.loyalty!;
    expect([p.name, p.unit, p.categoryIds], ['BerryCard', 'stempel', ['kopi']]);
    expect(p.rewards.map((r) => r.effect(r.productId == null ? null : menu.product(r.productId!)!.name)),
        ['Potongan Rp 5.000', 'Gratis 1 Latte', 'Potongan 10%']);
    expect(menuWith({'earn_mode': 'per_amount', 'earn_per_amount': 10000}).loyalty!.earnRule(), '1 poin tiap belanja Rp 10.000');
    expect(Menu.fromJson({...loyaltyMenuJson, 'loyalty': null}).loyalty, isNull);
  });

  group('harga dengan hadiah = server (OrderService::applyReward)', () {
    test('gratis produk memotong harga dasar 1 porsi; tambahan tetap dibayar', () {
      final (c, cart) = cartWith([(latte, [shot], 2)]);
      final line = c.read(cartProvider).lines.single;
      cart.setReward(reward('r-free'), itemId: line.id);
      final totals = priceCart(c.read(cartProvider), menu);
      expect(totals.lineDiscounts, [20000]);
      expect(totals.grandTotal, 30000); // 2 × 25.000 − 20.000
      expect(rewardDiscount(c.read(cartProvider), totals), 20000);
      expect(c.read(cartProvider).toJson(totals.grandTotal)['reward'], {'id': 'r-free', 'item_id': line.id});
    });

    test('potongan Rp dibatasi subtotal; potongan % dari subtotal', () {
      final (c, cart) = cartWith([(roti, [], 1)]);
      cart.setReward(const LoyaltyReward(id: 'big', name: 'Potongan 50rb', cost: 1, type: 'amount', value: 50000));
      expect(priceCart(c.read(cartProvider), menu).grandTotal, 0);

      cart.setReward(reward('r-pct'));
      final totals = priceCart(c.read(cartProvider), menu);
      expect([totals.orderDiscount, totals.grandTotal], [1000, 9000]);
      expect(c.read(cartProvider).toJson(0)['reward'], {'id': 'r-pct', 'item_id': null});
    });

    test('hadiah potongan menggantikan diskon order manual; gratis produk melepas diskon barisnya', () {
      final (c, cart) = cartWith([(latte, [], 1), (roti, [], 1)]);
      cart.setOrderDiscount(const Discount.amount(1000));
      cart.setReward(reward('r-amount'));
      expect(c.read(cartProvider).orderDiscount, isNull);

      final lineId = c.read(cartProvider).lines.first.id;
      cart.clearReward();
      cart.setLineDiscount(lineId, const Discount.amount(2000));
      cart.setReward(reward('r-free'), itemId: lineId);
      expect(c.read(cartProvider).lines.first.discount, isNull);
    });

    test('hadiah lepas bila baris hadiahnya dihapus atau member dilepas', () {
      final (c, cart) = cartWith([(latte, [], 1), (roti, [], 1)]);
      final lineId = c.read(cartProvider).lines.first.id;
      cart.setReward(reward('r-free'), itemId: lineId);
      cart.setQty(lineId, 0);
      expect(c.read(cartProvider).reward, isNull);

      cart.setReward(reward('r-amount'));
      cart.clearCustomer();
      expect([c.read(cartProvider).reward, c.read(cartProvider).customer], [null, null]);
    });
  });

  group('perkiraan stempel / poin', () {
    test('per item: hanya kategori terpilih, porsi gratis tidak dihitung', () {
      final (c, cart) = cartWith([(latte, [], 3), (roti, [], 2)]);
      expect(loyaltyEarnPreview(c.read(cartProvider), menu, priceCart(c.read(cartProvider), menu)), 3);
      cart.setReward(reward('r-free'), itemId: c.read(cartProvider).lines.first.id);
      expect(loyaltyEarnPreview(c.read(cartProvider), menu, priceCart(c.read(cartProvider), menu)), 2);
    });

    test('per transaksi dengan minimal belanja & poin per kelipatan', () {
      final (c, _) = cartWith([(latte, [], 2), (roti, [], 1)]); // 50.000
      final state = c.read(cartProvider);
      final perOrder = menuWith({'earn_mode': 'per_order', 'earn_min_order': 60000});
      expect(loyaltyEarnPreview(state, perOrder, priceCart(state, perOrder)), 0);
      final perAmount = menuWith({'earn_mode': 'per_amount', 'earn_per_amount': 10000});
      expect(loyaltyEarnPreview(state, perAmount, priceCart(state, perAmount)), 5);
    });

    test('tanpa member: tidak ada perkiraan', () {
      final (c, cart) = cartWith([(latte, [], 1)]);
      cart.clearCustomer();
      expect(loyaltyEarnPreview(c.read(cartProvider), menu, priceCart(c.read(cartProvider), menu)), 0);
    });
  });

  test('open bill berhadiah dimuat lagi: dari menu, atau direka ulang bila hadiahnya sudah nonaktif', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    Map<String, dynamic> saved(String rewardId, {String? itemId}) => {
          ...order(status: 'open'),
          'items': [
            {'id': 'i1', 'product_id': 'latte', 'name': 'Latte', 'unit_price': 20000, 'modifiers_total': 0, 'qty': 2,
              'note': null, 'discount': null, 'discount_total': 20000, 'line_total': 20000, 'modifiers': []},
          ],
          'customer': {'id': 'c1', 'code': 'M0001', 'name': 'Andi', 'anonymized': false},
          'reward': {'id': rewardId, 'name': 'Gratis Latte', 'cost': 3, 'item_id': itemId, 'discount': 20000},
        };

    container.read(cartProvider.notifier).loadOrder(saved('r-free', itemId: 'i1'), menu);
    var state = container.read(cartProvider);
    expect([state.reward?.type, state.rewardItemId, priceCart(state, menu).grandTotal], ['free_product', 'i1', 20000]);

    container.read(cartProvider.notifier).loadOrder(saved('gone', itemId: 'i1'), menu);
    state = container.read(cartProvider);
    expect([state.reward?.type, state.reward?.productId, priceCart(state, menu).grandTotal], ['free_product', 'latte', 20000]);
  });

  test('struk: label hadiah & ringkasan stempel member', () {
    final text = customerReceipt({
      ...order(),
      'reward': {'id': 'r', 'name': 'Gratis Latte', 'cost': 3, 'item_id': 'i2', 'discount': 4600},
      'loyalty': {'program': 'BerryCard', 'unit': 'stempel', 'earned': 1, 'redeemed': 3, 'balance': 7},
    }).join('\n');
    expect(text, contains('Hadiah'));
    expect(text, contains('BerryCard'));
    expect(text, contains('+1 stempel'));
    expect(text, contains('-3 stempel'));
    expect(text, contains('7 stempel'));

    final amount = customerReceipt({
      ...order(),
      'reward': {'id': 'r', 'name': 'Potongan 5rb', 'cost': 2, 'item_id': null, 'discount': 5000},
    }).join('\n');
    expect(amount, contains('Hadiah Potongan 5rb'));
    expect(customerReceipt(order()).join('\n'), isNot(contains('Saldo')));
  });
}
