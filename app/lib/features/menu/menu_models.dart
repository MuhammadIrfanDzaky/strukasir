/// Model menu dari `GET /menu`. Kelas Dart biasa (tanpa code generation) supaya mudah dibaca.
library;

import '../cart/pricing.dart';
import '../customers/member_tier.dart';
import '../loyalty/loyalty_models.dart';
import '../promotions/promotion_models.dart';

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
    this.allowQuantity = false,
    this.maxQuantity = 1,
  });

  factory MenuModifierGroup.fromJson(Map<String, dynamic> j) => MenuModifierGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        minSelect: j['min_select'] as int,
        maxSelect: j['max_select'] as int,
        allowQuantity: j['allow_quantity'] as bool? ?? false,
        maxQuantity: j['max_quantity'] as int? ?? 1,
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

  /// Satu opsi boleh dipilih lebih dari sekali (mis. Extra shot x2), maks. [maxQuantity] per opsi.
  /// Untuk grup ini [maxSelect] = batas total jumlah di grup.
  final bool allowQuantity;
  final int maxQuantity;

  bool get required => minSelect > 0;

  List<MenuModifier> get activeModifiers => modifiers.where((m) => m.active).toList();

  /// Keterangan aturan pilih untuk kasir, mis. "Wajib pilih 1" / "Opsional, maks 2".
  String get rule {
    // Grup berjumlah: batasnya total jumlah (mis. 2 Extra shot + 1 Sirup = 3).
    if (allowQuantity) return minSelect > 0 ? 'Pilih $minSelect–$maxSelect (total)' : 'Opsional, maks $maxSelect (total)';
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
    this.code,
    this.cost,
    this.recipeCost,
    this.favorite = false,
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
        code: j['code'] as String?,
        cost: j['cost'] as int?,
        recipeCost: j['recipe_cost'] as int?,
        favorite: j['favorite'] as bool? ?? false,
      );

  final String id;
  final String categoryId;
  final String name;
  final int price;
  final bool active;
  final bool soldOut;
  final int sort;
  final List<String> modifierGroupIds;

  /// Kode produk (SKU) buatan owner, mis. "BB03".
  final String? code;

  /// Harga modal (HPP). Hanya dikirim server ke user yang boleh mengelola menu; null = belum diisi.
  final int? cost;

  /// HPP dari resep (fitur stok, hanya untuk owner); bila ada, menggantikan [cost] di laporan.
  final int? recipeCost;

  /// Modal yang dipakai server untuk laba: HPP resep, atau modal manual.
  int? get effectiveCost => recipeCost ?? cost;

  /// Tampil di filter "Favorit" layar kasir.
  final bool favorite;

  bool get sellable => active && !soldOut;

  /// Margin terhadap harga jual (%), null bila modal belum diisi atau harga 0.
  double? get marginPercent => effectiveCost == null || price == 0 ? null : (price - effectiveCost!) * 100 / price;

  /// Cocok dengan kata kunci pencarian (nama atau kode, tanpa beda huruf besar/kecil).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q) || (code?.toLowerCase().contains(q) ?? false);
  }
}

/// Identitas struk kedai: nama, alamat (header), pesan penutup (footer), logo PNG base64.
class ReceiptSettings {
  const ReceiptSettings({this.name = '', this.header, this.footer, this.logoBase64});

  factory ReceiptSettings.fromJson(Map<String, dynamic>? j) => j == null
      ? const ReceiptSettings()
      : ReceiptSettings(
          name: j['name'] as String? ?? '',
          header: j['header'] as String?,
          footer: j['footer'] as String?,
          logoBase64: j['logo'] as String?,
        );

  final String name;
  final String? header;
  final String? footer;
  final String? logoBase64;
}

/// Outlet tablet ini (multi-outlet). Nama tampil di kasir & struk bila usaha punya lebih dari satu outlet.
class MenuOutlet {
  const MenuOutlet({required this.id, required this.name, this.code = '', this.address});

  factory MenuOutlet.fromJson(Map<String, dynamic> j) =>
      MenuOutlet(id: j['id'] as String, name: j['name'] as String, code: j['code'] as String? ?? '', address: j['address'] as String?);

  final String id;
  final String name;
  final String code;
  final String? address;
}

class Menu {
  const Menu({
    required this.version,
    this.receipt = const ReceiptSettings(),
    this.outlet,
    this.outletCount = 1,
    required this.pricing,
    required this.cashierDiscountLimitBp,
    required this.features,
    this.customerLabelHint = 'Nama pelanggan / meja',
    this.customerPhoneRequired = true,
    this.loyalty,
    this.memberTiers = const [],
    this.promotions = const [],
    required this.categories,
    required this.products,
    required this.modifierGroups,
  });

  factory Menu.fromJson(Map<String, dynamic> j) => Menu(
        version: j['version'] as String,
        receipt: ReceiptSettings.fromJson(j['receipt'] as Map<String, dynamic>?),
        outlet: j['outlet'] == null ? null : MenuOutlet.fromJson(j['outlet'] as Map<String, dynamic>),
        outletCount: j['outlet_count'] as int? ?? 1,
        pricing: PricingSettings.fromJson(j['pricing'] as Map<String, dynamic>),
        cashierDiscountLimitBp: (j['pricing'] as Map<String, dynamic>)['cashier_discount_limit_bp'] as int,
        features: (j['features'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as bool)),
        customerLabelHint: j['customer_label_hint'] as String? ?? 'Nama pelanggan / meja',
        customerPhoneRequired: j['customer_phone_required'] as bool? ?? true,
        loyalty: j['loyalty'] == null ? null : LoyaltyProgram.fromJson(j['loyalty'] as Map<String, dynamic>),
        memberTiers: ((j['member_tiers'] as List?) ?? const []).cast<Map<String, dynamic>>().map(MemberTier.fromJson).toList(),
        promotions: ((j['promotions'] as List?) ?? const []).cast<Map<String, dynamic>>().map(Promotion.fromJson).toList(),
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
  final ReceiptSettings receipt;

  /// Outlet tablet ini (null = server lama).
  final MenuOutlet? outlet;

  /// Jumlah outlet aktif; > 1 → nama outlet tampil & laporan/stok bisa dipilih per outlet.
  final int outletCount;

  bool get multiOutlet => outletCount > 1;
  final PricingSettings pricing;
  final int cashierDiscountLimitBp;
  final Map<String, bool> features;

  /// Label kolom nama di kasir sesuai cara jualan ("Nama pelanggan" untuk bawa pulang saja).
  final String customerLabelHint;

  /// Form "Pelanggan baru" di kasir: no HP wajib (Pengaturan → Fitur).
  final bool customerPhoneRequired;

  /// Program loyalitas yang berjalan (null = tidak ada / fitur mati).
  final LoyaltyProgram? loyalty;

  /// Tingkat member aktif, ambang terendah dulu (kosong = fitur mati).
  final List<MemberTier> memberTiers;

  /// Promo otomatis aktif (urut nama, sama dengan server); berlaku sesuai jadwalnya.
  final List<Promotion> promotions;
  final List<MenuCategory> categories;

  bool feature(String key) => features[key] ?? false;

  /// Nama pelanggan / meja wajib (Pengaturan → Fitur). Server lama tanpa kunci ini = wajib.
  bool get customerNameOn => features['customer_name'] ?? true;

  /// Varian produk aktif; mati → produk langsung masuk keranjang tanpa dialog pilihan.
  bool get modifiersOn => features['modifiers'] ?? true;

  /// Pelanggan / member (fitur paket). Server lama tanpa kunci ini = tidak ada.
  bool get customersOn => features['customers'] ?? false;

  MenuProduct? product(String id) => products.where((p) => p.id == id).firstOrNull;
  final List<MenuProduct> products;
  final List<MenuModifierGroup> modifierGroups;

  List<MenuCategory> get activeCategories => categories.where((c) => c.active).toList();

  List<MenuProduct> productsIn(String categoryId, {bool includeInactive = false}) => products
      .where((p) => p.categoryId == categoryId && (includeInactive || p.active))
      .toList();

  /// Produk aktif di kategori, urut abjad (tanpa beda huruf besar/kecil) — urutan di layar kasir.
  List<MenuProduct> productsByName(String categoryId) => sortByName(productsIn(categoryId));

  static List<MenuProduct> sortByName(Iterable<MenuProduct> products) =>
      [...products]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<MenuModifierGroup> groupsFor(MenuProduct product) => [
        for (final id in product.modifierGroupIds)
          ...modifierGroups.where((g) => g.id == id),
      ];

  MenuCategory? category(String id) => categories.where((c) => c.id == id).firstOrNull;
}
