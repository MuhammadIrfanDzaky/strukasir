import 'dart:convert';
import 'dart:io';

import 'package:berrybrew_pos/features/cart/pricing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixture yang sama dengan backend (Tests\Unit\PricingServiceTest): total tablet = total server.
void main() {
  final fixture = jsonDecode(File('../docs/pricing-fixtures.json').readAsStringSync()) as Map<String, dynamic>;

  for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test(c['name'] as String, () {
      final s = c['settings'] as Map<String, dynamic>;
      final items = (c['items'] as List).cast<Map<String, dynamic>>().map((i) => PricingLine(
            unitPrice: i['unit_price'] as int,
            qty: i['qty'] as int,
            discount: i['discount'] == null ? null : Discount.fromJson(i['discount'] as Map<String, dynamic>),
          ));
      final orderDiscount =
          c['order_discount'] == null ? null : Discount.fromJson(c['order_discount'] as Map<String, dynamic>);

      final result = calculatePrice(items.toList(), orderDiscount, PricingSettings.fromJson(s));

      expect(result.toJson(), c['expected']);
    });
  }

  test('menolak diskon nominal lebih besar dari harga', () {
    expect(
      () => calculatePrice([const PricingLine(unitPrice: 13000, qty: 1, discount: Discount.amount(13001))], null,
          const PricingSettings()),
      throwsA(isA<PricingException>()),
    );
  });
}
