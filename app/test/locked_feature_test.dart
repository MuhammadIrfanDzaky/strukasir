import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loyalty_test.dart' show loyaltyMenuJson;

void main() {
  test('fitur terkunci dari menu: label & paket pembuka', () {
    final menu = Menu.fromJson({
      ...loyaltyMenuJson,
      'locked_features': [
        {'key': 'inventory', 'label': 'Stok & resep', 'description': 'Stok bahan', 'plan': {'code': 'tumbuh', 'name': 'Tumbuh'}},
      ],
    });
    expect(menu.locked('inventory')?.planName, 'Tumbuh');
    expect(menu.locked('promotions'), isNull);
    expect(Menu.fromJson(loyaltyMenuJson).lockedFeatures, isEmpty, reason: 'cache menu dari server lama');
  });
}
