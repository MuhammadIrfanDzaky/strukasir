import '../../core/money.dart';

/// Bahan baku (fitur `inventory`). Jumlah dalam satuan dasar g / ml / pcs.
class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    this.stock = 0,
    this.minStock,
    this.avgCost = 0,
    this.value = 0,
    this.low = false,
    this.active = true,
    this.usedIn = 0,
  });

  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
    id: j['id'] as String,
    name: j['name'] as String,
    unit: j['unit'] as String,
    stock: (j['stock'] as num).toDouble(),
    minStock: (j['min_stock'] as num?)?.toDouble(),
    avgCost: (j['avg_cost'] as num? ?? 0).toDouble(),
    value: j['value'] as int? ?? 0,
    low: j['low'] as bool? ?? false,
    active: j['active'] as bool? ?? true,
    usedIn: j['used_in'] as int? ?? 0,
  );

  final String id;
  final String name;
  final String unit;
  final double stock;
  final double? minStock;

  /// Modal rata-rata, Rp per satuan dasar.
  final double avgCost;

  /// Nilai stok (Rp) = stok positif × modal rata-rata.
  final int value;
  final bool low;
  final bool active;

  /// Jumlah resep (produk/varian) yang memakai bahan ini.
  final int usedIn;

  bool get negative => stock < 0;

  /// "1.350 ml"
  String get stockText => '${qtyText(stock)} $unit';

  /// "Rp20/ml" — modal per satuan; < Rp10 ditampilkan dengan desimal.
  String get costText => avgCost == 0 ? 'modal belum ada' : '${costPerUnit(avgCost)}/$unit';
}

/// Satu baris resep: pemakaian bahan per 1 porsi / per 1 pilihan varian (boleh minus untuk varian pengganti).
class RecipeLine {
  const RecipeLine(this.ingredientId, this.qty);

  factory RecipeLine.fromJson(Map<String, dynamic> j) => RecipeLine(j['ingredient_id'] as String, (j['qty'] as num).toDouble());

  final String ingredientId;
  final double qty;

  Map<String, dynamic> toJson() => {'ingredient_id': ingredientId, 'qty': qty};
}

class InventoryData {
  const InventoryData({
    required this.ingredients,
    required this.productRecipes,
    required this.modifierRecipes,
    required this.productCosts,
    required this.value,
    required this.lowCount,
  });

  factory InventoryData.fromJson(Map<String, dynamic> j) {
    Map<String, List<RecipeLine>> recipes(Object? raw) =>
        raw is Map ? raw.map((k, v) => MapEntry(k as String, (v as List).cast<Map<String, dynamic>>().map(RecipeLine.fromJson).toList())) : const {};
    final r = j['recipes'] as Map<String, dynamic>? ?? const {};
    final summary = j['summary'] as Map<String, dynamic>? ?? const {};
    return InventoryData(
      ingredients: (j['ingredients'] as List).cast<Map<String, dynamic>>().map(Ingredient.fromJson).toList(),
      productRecipes: recipes(r['products']),
      modifierRecipes: recipes(r['modifiers']),
      productCosts: (j['product_costs'] as Map? ?? const {}).map((k, v) => MapEntry(k as String, v as int)),
      value: summary['value'] as int? ?? 0,
      lowCount: summary['low'] as int? ?? 0,
    );
  }

  final List<Ingredient> ingredients;
  final Map<String, List<RecipeLine>> productRecipes;
  final Map<String, List<RecipeLine>> modifierRecipes;

  /// HPP per produk dari resep (Rp, dibulatkan).
  final Map<String, int> productCosts;
  final int value;
  final int lowCount;

  Ingredient? ingredient(String id) => ingredients.where((i) => i.id == id).firstOrNull;

  /// HPP resep (Rp, boleh minus untuk varian pengganti) = Σ qty × modal rata-rata. Sama dengan server.
  double costOf(List<RecipeLine> lines) => lines.fold(0, (sum, l) => sum + l.qty * (ingredient(l.ingredientId)?.avgCost ?? 0));

  /// Ringkasan resep: "Biji kopi 18 g, Susu 150 ml".
  String summary(List<RecipeLine> lines) =>
      lines.map((l) => '${ingredient(l.ingredientId)?.name ?? '?'} ${qtyText(l.qty)} ${ingredient(l.ingredientId)?.unit ?? ''}').join(', ');
}

/// Jumlah gaya Indonesia tanpa nol berlebih: 1350 → "1.350", 2.5 → "2,5", -150 → "-150".
String qtyText(double qty) {
  final negative = qty < 0;
  final abs = qty.abs();
  final whole = abs.truncate();
  final frac = ((abs - whole) * 1000).round();
  final fracText = frac == 0 ? '' : ',${frac.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
  return '${negative ? '-' : ''}${rupiah(whole)}$fracText';
}

/// Input jumlah: koma = desimal, titik = pemisah ribuan ("1.000" = 1000, "2,5" = 2.5). Null bila tidak valid.
double? parseQty(String input) {
  final t = input.trim().replaceAll(' ', '').replaceAll('.', '').replaceAll(',', '.');
  if (t.isEmpty || t == '-') return null;
  final v = double.tryParse(t);
  return v == null ? null : (v * 1000).round() / 1000;
}

/// Modal per satuan: Rp20 / Rp0,25.
String costPerUnit(double cost) {
  if (cost >= 10) return 'Rp${rupiah(cost.round())}';
  final s = cost.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '').replaceAll('.', ',');
  return 'Rp$s';
}

/// Satuan besar untuk input pembelian (×1000): g → kg, ml → L.
String? bigUnit(String unit) => switch (unit) {
  'g' => 'kg',
  'ml' => 'L',
  _ => null,
};
