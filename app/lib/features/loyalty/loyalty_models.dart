import '../../core/money.dart';

/// Program loyalitas kedai (bagian `loyalty` dari GET /menu dan GET /settings/loyalty).
class LoyaltyProgram {
  const LoyaltyProgram({
    required this.active,
    required this.name,
    required this.earnMode,
    this.earnPerAmount,
    this.earnMinOrder,
    this.categoryIds = const [],
    this.expiryMonths,
    this.rewards = const [],
  });

  factory LoyaltyProgram.fromJson(Map<String, dynamic> j, {List<dynamic>? rewards}) => LoyaltyProgram(
        active: j['active'] as bool? ?? true,
        name: j['name'] as String,
        earnMode: j['earn_mode'] as String,
        earnPerAmount: j['earn_per_amount'] as int?,
        earnMinOrder: j['earn_min_order'] as int?,
        categoryIds: ((j['category_ids'] as List?) ?? const []).cast<String>(),
        expiryMonths: j['expiry_months'] as int?,
        rewards: (rewards ?? (j['rewards'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(LoyaltyReward.fromJson)
            .toList(),
      );

  final bool active;
  final String name;

  /// per_item | per_order | per_amount
  final String earnMode;
  final int? earnPerAmount;
  final int? earnMinOrder;

  /// per_item: kategori yang menghasilkan stempel; kosong = semua produk.
  final List<String> categoryIds;
  final int? expiryMonths;
  final List<LoyaltyReward> rewards;

  /// "stempel" atau "poin".
  String get unit => earnMode == 'per_amount' ? 'poin' : 'stempel';

  /// Kalimat aturan untuk owner & kasir, mis. "1 stempel tiap beli 1 item".
  String earnRule({String Function(List<String> ids)? categoryNames}) => switch (earnMode) {
        'per_order' => (earnMinOrder ?? 0) > 0
            ? '1 stempel tiap transaksi minimal ${rp(earnMinOrder!)}'
            : '1 stempel tiap transaksi',
        'per_amount' => '1 poin tiap belanja ${rp(earnPerAmount ?? 0)}',
        _ => categoryIds.isEmpty || categoryNames == null
            ? '1 stempel tiap beli 1 item'
            : '1 stempel tiap beli 1 item ${categoryNames(categoryIds)}',
      };
}

/// Hadiah yang bisa ditukar.
class LoyaltyReward {
  const LoyaltyReward({
    required this.id,
    required this.name,
    required this.cost,
    required this.type,
    this.productId,
    this.value = 0,
  });

  factory LoyaltyReward.fromJson(Map<String, dynamic> j) => LoyaltyReward(
        id: j['id'] as String,
        name: j['name'] as String,
        cost: j['cost'] as int,
        type: j['type'] as String,
        productId: j['product_id'] as String?,
        value: j['value'] as int? ?? 0,
      );

  final String id;
  final String name;

  /// Harga dalam stempel / poin.
  final int cost;

  /// free_product | amount | percent
  final String type;
  final String? productId;

  /// Rp (amount) atau basis poin (percent: 1000 = 10%).
  final int value;

  bool get isFreeProduct => type == 'free_product';

  /// Penjelasan singkat efek hadiah, mis. "Potongan Rp 5.000", "Potongan 10%".
  String effect(String? productName) => switch (type) {
        'free_product' => 'Gratis 1 ${productName ?? 'produk'}',
        'percent' => 'Potongan ${percentBp(value)}',
        _ => 'Potongan ${rp(value)}',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cost': cost,
        'type': type,
        'product_id': productId,
        'value': value,
      };
}
