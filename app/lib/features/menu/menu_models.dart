/// Model menu dari `GET /menu`. Kelas Dart biasa (tanpa code generation) supaya mudah dibaca.
library;

class MenuCategory {
  const MenuCategory({required this.id, required this.name, required this.sort, required this.active});

  factory MenuCategory.fromJson(Map<String, dynamic> j) => MenuCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        sort: j['sort'] as int,
        active: j['active'] as bool,
      );

  final String id;
  final String name;
  final int sort;
  final bool active;
}

class MenuModifier {
  const MenuModifier({
    required this.id,
    required this.name,
    required this.priceDelta,
    required this.active,
  });

  factory MenuModifier.fromJson(Map<String, dynamic> j) => MenuModifier(
        id: j['id'] as String,
        name: j['name'] as String,
        priceDelta: j['price_delta'] as int,
        active: j['active'] as bool,
      );

  final String id;
  final String name;
  final int priceDelta;
  final bool active;
}

class MenuModifierGroup {
  const MenuModifierGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.modifiers,
  });

  factory MenuModifierGroup.fromJson(Map<String, dynamic> j) => MenuModifierGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        minSelect: j['min_select'] as int,
        maxSelect: j['max_select'] as int,
        modifiers: (j['modifiers'] as List)
            .cast<Map<String, dynamic>>()
            .map(MenuModifier.fromJson)
            .toList(),
      );

  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<MenuModifier> modifiers;

  bool get required => minSelect > 0;

  List<MenuModifier> get activeModifiers => modifiers.where((m) => m.active).toList();

  /// Keterangan aturan pilih untuk kasir, mis. "Wajib pilih 1" / "Opsional, maks 2".
  String get rule {
    if (minSelect == maxSelect) return 'Wajib pilih $minSelect';
    if (minSelect > 0) return 'Pilih $minSelect–$maxSelect';
    return maxSelect == 1 ? 'Opsional' : 'Opsional, maks $maxSelect';
  }
}

class MenuProduct {
  const MenuProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    required this.active,
    required this.soldOut,
    required this.sort,
    required this.modifierGroupIds,
  });

  factory MenuProduct.fromJson(Map<String, dynamic> j) => MenuProduct(
        id: j['id'] as String,
        categoryId: j['category_id'] as String,
        name: j['name'] as String,
        price: j['price'] as int,
        active: j['active'] as bool,
        soldOut: j['sold_out'] as bool,
        sort: j['sort'] as int,
        modifierGroupIds: (j['modifier_group_ids'] as List).cast<String>(),
      );

  final String id;
  final String categoryId;
  final String name;
  final int price;
  final bool active;
  final bool soldOut;
  final int sort;
  final List<String> modifierGroupIds;

  bool get sellable => active && !soldOut;
}

class Menu {
  const Menu({
    required this.version,
    required this.categories,
    required this.products,
    required this.modifierGroups,
  });

  factory Menu.fromJson(Map<String, dynamic> j) => Menu(
        version: j['version'] as String,
        categories: (j['categories'] as List)
            .cast<Map<String, dynamic>>()
            .map(MenuCategory.fromJson)
            .toList(),
        products: (j['products'] as List)
            .cast<Map<String, dynamic>>()
            .map(MenuProduct.fromJson)
            .toList(),
        modifierGroups: (j['modifier_groups'] as List)
            .cast<Map<String, dynamic>>()
            .map(MenuModifierGroup.fromJson)
            .toList(),
      );

  final String version;
  final List<MenuCategory> categories;
  final List<MenuProduct> products;
  final List<MenuModifierGroup> modifierGroups;

  List<MenuCategory> get activeCategories => categories.where((c) => c.active).toList();

  List<MenuProduct> productsIn(String categoryId, {bool includeInactive = false}) => products
      .where((p) => p.categoryId == categoryId && (includeInactive || p.active))
      .toList();

  List<MenuModifierGroup> groupsFor(MenuProduct product) => [
        for (final id in product.modifierGroupIds)
          ...modifierGroups.where((g) => g.id == id),
      ];

  MenuCategory? category(String id) => categories.where((c) => c.id == id).firstOrNull;
}
