import 'package:berrybrew_pos/features/inventory/inventory_models.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'menu_test.dart' show menuJson;

void main() {
  test('jumlah gaya Indonesia: tampil & input', () {
    expect([qtyText(1350), qtyText(2.5), qtyText(-150), qtyText(0.125), qtyText(1000000)], ['1.350', '2,5', '-150', '0,125', '1.000.000']);
    expect([parseQty('1.000'), parseQty('2,5'), parseQty('-150'), parseQty('0,1234'), parseQty(''), parseQty('-')], [1000, 2.5, -150, 0.123, null, null]);
    expect([costPerUnit(20), costPerUnit(210.5), costPerUnit(0.25), costPerUnit(2.5)], ['Rp20', 'Rp211', 'Rp0,25', 'Rp2,5']);
    expect([bigUnit('g'), bigUnit('ml'), bigUnit('pcs')], ['kg', 'L', null]);
  });

  test('HPP resep = Σ qty × modal rata-rata (sama dengan server); varian pengganti boleh minus', () {
    final data = InventoryData.fromJson({
      'ingredients': [
        {'id': 'kopi', 'name': 'Biji kopi', 'unit': 'g', 'stock': 1000, 'avg_cost': 200},
        {'id': 'susu', 'name': 'Susu', 'unit': 'ml', 'stock': 2000, 'avg_cost': 20},
        {'id': 'oat', 'name': 'Oat', 'unit': 'ml', 'stock': -5, 'avg_cost': 50, 'low': true},
      ],
      'recipes': {
        'products': {'p1': [{'ingredient_id': 'kopi', 'qty': 18}, {'ingredient_id': 'susu', 'qty': 150}]},
        'modifiers': {'oat': [{'ingredient_id': 'oat', 'qty': 150}, {'ingredient_id': 'susu', 'qty': -150}]},
      },
      'product_costs': {'p1': 6600},
      'summary': {'value': 240000, 'low': 1},
    });
    expect(data.costOf(data.productRecipes['p1']!), 6600);
    expect(data.costOf(data.modifierRecipes['oat']!), 4500);
    expect(data.summary(data.productRecipes['p1']!), 'Biji kopi 18 g, Susu 150 ml');
    expect(data.ingredient('oat')!.negative, isTrue);
    expect(data.ingredient('oat')!.stockText, '-5 ml');
    expect(data.ingredient('susu')!.costText, 'Rp20/ml');
    expect([data.value, data.lowCount], [240000, 1]);
  });

  test('HPP resep menggantikan modal manual untuk margin', () {
    final p = MenuProduct.fromJson({...(menuJson['products'] as List).first as Map<String, dynamic>, 'cost': 9000, 'recipe_cost': 6500});
    expect(p.effectiveCost, 6500);
    expect(p.marginPercent!.round(), 50);
    expect(MenuProduct.fromJson({...(menuJson['products'] as List).first as Map<String, dynamic>, 'cost': 9000}).effectiveCost, 9000);
  });
}
