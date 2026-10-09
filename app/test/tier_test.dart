import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/cart/pricing.dart';
import 'package:berrybrew_pos/features/customers/member_tier.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/menu/modifier_selection.dart';
import 'package:berrybrew_pos/features/printing/receipt_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loyalty_test.dart' show loyaltyMenuJson;
import 'receipt_format_test.dart' show order;

void main() {
  final menu = Menu.fromJson({
    ...loyaltyMenuJson,
    'member_tiers': [
      {'id': 't-silver', 'name': 'Silver', 'threshold': 40000, 'discount_bp': 500, 'earn_multiplier': 1, 'color': 'silver'},
      {'id': 't-gold', 'name': 'Gold', 'threshold': 100000, 'discount_bp': 1500, 'earn_multiplier': 2, 'color': 'gold'},
    ],
  });
  final latte = menu.product('latte')!;
  final roti = menu.product('roti')!;
  final gold = menu.memberTiers.last;

  (ProviderContainer, CartController) cart(MemberTier? tier) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(cartProvider.notifier);
    c.add(ModifierSelection(latte, menu.groupsFor(latte)));
    c.add(ModifierSelection(roti, const []));
    c.setCustomer(CartCustomer(id: 'c1', code: 'M0001', name: 'Andi', tier: tier));
    return (container, c);
  }

  test('tingkat dibaca dari menu; manfaat tertulis', () {
    expect(menu.memberTiers.map((t) => t.name), ['Silver', 'Gold']);
    expect(gold.benefits, 'diskon 15% · stempel/poin 2×');
    expect(const MemberTier(id: 'x', name: 'Basic').benefits, '');
    expect(Menu.fromJson(loyaltyMenuJson).memberTiers, isEmpty);
  });

  test('diskon tingkat di baris tanpa diskon = server (OrderService::applyTier)', () {
    final (c, notifier) = cart(gold);
    var totals = priceCart(c.read(cartProvider), menu);
    expect(totals.lineDiscounts, [3000, 1500]); // 15% dari 20.000 & 10.000
    expect(totals.grandTotal, 25500);
    expect(c.read(cartProvider).toJson(0)['tier_id'], 't-gold');

    // Baris diskon manual tidak ikut diskon tingkat.
    notifier.setLineDiscount(c.read(cartProvider).lines.last.id, const Discount.amount(1000));
    totals = priceCart(c.read(cartProvider), menu);
    expect(totals.lineDiscounts, [3000, 1000]);
    final now = DateTime(2026, 10, 14, 10);
    expect(lineBenefit(c.read(cartProvider), menu, c.read(cartProvider).lines.first, now)?.label, 'Diskon member');
    expect(lineBenefit(c.read(cartProvider), menu, c.read(cartProvider).lines.last, now), isNull);
  });

  test('baris hadiah gratis tidak ikut diskon tingkat; stempel dikali pengali tingkat', () {
    final (c, notifier) = cart(gold);
    final reward = menu.loyalty!.rewards.firstWhere((r) => r.isFreeProduct);
    notifier.setReward(reward, itemId: c.read(cartProvider).lines.first.id);
    final totals = priceCart(c.read(cartProvider), menu);
    expect(totals.lineDiscounts, [20000, 1500]);
    // 1 latte (kopi) gratis → 0 stempel dasar; tanpa hadiah 1 × 2 = 2.
    expect(loyaltyEarnPreview(c.read(cartProvider), menu, totals), 0);
    notifier.clearReward();
    expect(loyaltyEarnPreview(c.read(cartProvider), menu, priceCart(c.read(cartProvider), menu)), 2);
  });

  test('member tanpa tingkat: tier_id null ikut terkirim (server memeriksa perubahan)', () {
    final (c, _) = cart(null);
    expect(c.read(cartProvider).toJson(0).containsKey('tier_id'), isTrue);
    expect(c.read(cartProvider).toJson(0)['tier_id'], isNull);
    expect(priceCart(c.read(cartProvider), menu).grandTotal, 30000);
  });

  test('open bill bertingkat dimuat lagi dengan tingkat dari salinan order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(cartProvider.notifier).loadOrder({
      ...order(status: 'open'),
      'items': [
        {'id': 'i1', 'product_id': 'latte', 'name': 'Latte', 'unit_price': 20000, 'modifiers_total': 0, 'qty': 1,
          'note': null, 'discount': null, 'discount_total': 3000, 'line_total': 17000, 'modifiers': []},
      ],
      'customer': {'id': 'c1', 'code': 'M0001', 'name': 'Andi', 'anonymized': false},
      'tier': {'id': 't-gold', 'name': 'Gold', 'discount_bp': 1500, 'earn_multiplier': 2, 'discount': 3000},
    }, menu);
    final state = container.read(cartProvider);
    expect([state.customer?.tier?.name, state.customer?.tier?.color], ['Gold', 'gold']);
    expect(priceCart(state, menu).grandTotal, 17000);
  });

  test('struk menulis tingkat & label diskon tingkat', () {
    final text = customerReceipt({
      ...order(),
      'customer': {'id': 'c1', 'code': 'M0001', 'name': 'Andi', 'anonymized': false},
      'tier': {'id': 't', 'name': 'Gold', 'discount_bp': 1500, 'earn_multiplier': 2, 'discount': 2000},
      'items': [
        {'id': 'i1', 'name': 'Latte', 'unit_price': 20000, 'modifiers_total': 0, 'qty': 1, 'note': null,
          'discount': null, 'discount_total': 3000, 'line_total': 17000, 'modifiers': []},
      ],
    }).join('\n');
    expect(text, contains('Member: M0001 (Gold)'));
    expect(text, contains('Diskon Gold'));
  });
}
