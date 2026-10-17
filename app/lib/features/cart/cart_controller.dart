import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/shop_clock.dart';
import '../menu/menu_controller.dart';
import '../menu/menu_models.dart';
import '../customers/member_tier.dart';
import '../loyalty/loyalty_models.dart';
import '../promotions/promotion_models.dart';
import '../menu/modifier_selection.dart';
import 'pricing.dart';

const _uuid = Uuid();

class CartLine {
  const CartLine({
    required this.id,
    required this.product,
    required this.modifiers,
    required this.qty,
    this.note,
    this.discount,
  });

  /// ID baris dibuat di tablet (UUID) dan dikirim ke server — kunci untuk "item baru vs lama".
  final String id;
  final MenuProduct product;
  final List<MenuModifier> modifiers;
  final int qty;
  final String? note;
  final Discount? discount;

  int get unitPrice => product.price + modifiers.fold(0, (s, m) => s + m.priceDelta);

  CartLine copyWith({int? qty, String? note, Discount? discount, bool clearDiscount = false}) => CartLine(
        id: id,
        product: product,
        modifiers: modifiers,
        qty: qty ?? this.qty,
        note: note ?? this.note,
        discount: clearDiscount ? null : (discount ?? this.discount),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': product.id,
        'qty': qty,
        'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
        'modifier_ids': modifiers.map((m) => m.id).toList(),
        'discount': discount?.toJson(),
      };
}

/// Member yang ditautkan ke order (cukup untuk tampilan kasir & struk).
class CartCustomer {
  const CartCustomer({required this.id, required this.code, required this.name, this.phone, this.visits, this.note, this.balance, this.tier, this.creditBalance, this.creditLimit});

  final String id;
  final String code;
  final String name;

  /// Tersamar untuk kasir (0812****7890).
  final String? phone;
  final int? visits;

  /// Catatan pelanggan (alergi, selera) — ditampilkan ke kasir.
  final String? note;

  /// Saldo stempel / poin saat dipilih (null = program tidak berjalan / tidak diketahui).
  final int? balance;

  /// Tingkat member (diskon otomatis & pengali stempel); dikirim ke server sebagai `tier_id`.
  final MemberTier? tier;

  /// Sisa kasbon & batasnya saat dipilih (null = fitur kasbon mati / batas tanpa batas).
  final int? creditBalance;
  final int? creditLimit;
}

class CartState {
  const CartState({
    required this.orderId,
    this.lines = const [],
    this.customerLabel = '',
    this.customer,
    this.reward,
    this.rewardItemId,
    this.orderDiscount,
    this.number,
    this.ticketed = const {},
    this.voucher,
    this.createdAt,
    this.orderType,
    this.tableLabel = '',
  });

  /// takeaway | dine_in; null = jenis awal kedai (Menu.defaultOrderType). Dipakai bila fitur aktif.
  final String? orderType;

  /// Nomor meja (dine-in).
  final String tableLabel;

  /// Jenis pesanan yang berlaku (null = fitur jenis pesanan mati).
  String? typeIn(Menu menu) => menu.orderTypesOn ? (orderType ?? menu.defaultOrderType) : null;

  /// Jam open bill dibuat di server (UTC); null = order baru. Jadwal promo dinilai pada jam ini.
  final DateTime? createdAt;

  /// UUID order dibuat di tablet = idempotency key. Kirim ulang aman.
  final String orderId;
  final List<CartLine> lines;
  final String customerLabel;

  /// Pelanggan / member (opsional, fitur `customers`).
  final CartCustomer? customer;

  /// Hadiah loyalitas yang ditukar (satu per order) dan baris yang digratiskan (hadiah gratis produk).
  final LoyaltyReward? reward;
  final String? rewardItemId;
  final Discount? orderDiscount;

  /// Nomor dari server bila order sudah pernah disimpan (open bill).
  final String? number;

  /// Qty per baris yang sudah dikirim ke bar/dapur (tiket); sisanya dicetak sebagai tambahan.
  final Map<String, int> ticketed;

  /// Voucher kode (diskon order); tidak digabung dengan diskon order manual / hadiah potongan.
  final VoucherTerms? voucher;

  bool get isEmpty => lines.isEmpty;
  bool get isSaved => number != null;
  int get itemCount => lines.fold(0, (s, l) => s + l.qty);

  CartState copyWith({
    List<CartLine>? lines,
    String? customerLabel,
    CartCustomer? customer,
    bool clearCustomer = false,
    LoyaltyReward? reward,
    String? rewardItemId,
    bool clearReward = false,
    Discount? orderDiscount,
    bool clearOrderDiscount = false,
    String? number,
    Map<String, int>? ticketed,
    VoucherTerms? voucher,
    bool clearVoucher = false,
    String? orderType,
    String? tableLabel,
  }) =>
      CartState(
        orderId: orderId,
        lines: lines ?? this.lines,
        customerLabel: customerLabel ?? this.customerLabel,
        customer: clearCustomer ? null : (customer ?? this.customer),
        reward: clearReward || clearCustomer ? null : (reward ?? this.reward),
        rewardItemId: clearReward || clearCustomer ? null : (rewardItemId ?? this.rewardItemId),
        orderDiscount: clearOrderDiscount ? null : (orderDiscount ?? this.orderDiscount),
        number: number ?? this.number,
        ticketed: ticketed ?? this.ticketed,
        voucher: clearVoucher ? null : (voucher ?? this.voucher),
        createdAt: createdAt,
        orderType: orderType ?? this.orderType,
        tableLabel: tableLabel ?? this.tableLabel,
      );

  Map<String, dynamic> toJson(int expectedTotal) => {
        'customer_label': customerLabel.trim().isEmpty ? null : customerLabel.trim(),
        'order_type': ?orderType,
        if (tableLabel.trim().isNotEmpty) 'table_label': tableLabel.trim(),
        'customer_id': customer?.id,
        if (customer != null) 'tier_id': customer!.tier?.id,
        if (reward != null) 'reward': {'id': reward!.id, 'item_id': rewardItemId},
        if (voucher != null) 'voucher_code': voucher!.code,
        'client_created_at': DateTime.now().toUtc().toIso8601String(),
        'expected_total': expectedTotal,
        'items': lines.map((l) => l.toJson()).toList(),
        'order_discount': orderDiscount?.toJson(),
      };
}

final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);

/// Detak jam untuk promo terjadwal: total keranjang dihitung ulang saat promo mulai/berakhir
/// (keranjang yang dibiarkan terbuka melewati jam promo tidak menampilkan total lama).
final promoTickProvider = StreamProvider<int>((ref) {
  final menu = ref.watch(menuProvider).value?.menu;
  final scheduled = menu?.promotions.any((p) => p.times != null || p.days != null || p.startsOn != null || p.endsOn != null) ?? false;
  return scheduled ? Stream.periodic(const Duration(seconds: 15), (i) => i) : const Stream.empty();
});

/// Jam penilaian promo: jam open bill dibuat (order lama) atau sekarang, dalam jam kedai.
DateTime promoTime(CartState cart, Menu menu) => ShopClock.wall(menu.utcOffset, cart.createdAt);

/// Total keranjang dihitung di tablet dengan aturan yang sama dengan server.
final cartTotalsProvider = Provider<PricingResult>((ref) {
  ref.watch(promoTickProvider);
  final cart = ref.watch(cartProvider);
  final menu = ref.watch(menuProvider).value?.menu;
  if (menu == null || cart.isEmpty) return PricingResult.empty;
  try {
    return priceCart(cart, menu);
  } on PricingException {
    return PricingResult.empty;
  }
});

/// Harga keranjang termasuk hadiah loyalitas & tingkat member, sama dengan OrderService di server:
/// gratis produk = potongan harga dasar 1 porsi di barisnya; potongan Rp (maks. subtotal) / % = diskon order;
/// tingkat member = diskon % di setiap baris yang belum punya diskon (manual / hadiah).
PricingResult priceCart(CartState cart, Menu menu, {DateTime? at}) {
  final reward = cart.reward;
  final benefits = lineBenefits(cart, menu, at ?? promoTime(cart, menu));
  // Service charge hanya untuk dine-in bila jenis pesanan aktif (sama dengan OrderService).
  final pricing = cart.typeIn(menu) == 'takeaway' ? menu.pricing.withoutService() : menu.pricing;
  final lines = [
    for (final (i, l) in cart.lines.indexed)
      PricingLine(
        unitPrice: l.unitPrice,
        qty: l.qty,
        discount: reward != null && reward.isFreeProduct && l.id == cart.rewardItemId
            ? Discount.amount(l.product.price)
            : l.discount ?? benefits[i]?.discount,
      ),
  ];
  var orderDiscount = cart.orderDiscount;
  if (reward != null && !reward.isFreeProduct) {
    if (reward.type == 'percent') {
      orderDiscount = Discount.percent(reward.value);
    } else {
      final subtotal = calculatePrice(lines, null, pricing).subtotal;
      orderDiscount = Discount.amount(reward.value < subtotal ? reward.value : subtotal);
    }
  } else if (cart.voucher != null && orderDiscount == null) {
    final d = cart.voucher!.discountFor(calculatePrice(lines, null, pricing).subtotal);
    if (d > 0) orderDiscount = Discount.amount(d);
  }
  return calculatePrice(lines, orderDiscount, pricing);
}

/// Diskon otomatis satu baris; lihat [lineBenefits].
({String label, Discount discount})? lineBenefit(CartState cart, Menu menu, CartLine l, DateTime at) {
  final i = cart.lines.indexWhere((x) => x.id == l.id);
  return i < 0 ? null : lineBenefits(cart, menu, at)[i];
}

/// Diskon otomatis per baris (tanpa diskon manual & bukan baris hadiah), sama dengan
/// OrderService::applyLineBenefits: paket bundling dulu (lintas baris), lalu per baris yang terbesar
/// antara promo berjalan dan tingkat member (seri → promo).
List<({String label, Discount discount})?> lineBenefits(CartState cart, Menu menu, DateTime at) {
  final running = [for (final p in menu.promotions) if (p.runsAt(at)) p];
  bool eligible(CartLine l) => l.discount == null && !(cart.reward?.isFreeProduct == true && l.id == cart.rewardItemId);
  final bundled = bundleDiscounts(running, [
    for (final l in cart.lines)
      eligible(l) ? (productId: l.product.id, price: l.product.price, qty: l.qty, gross: l.unitPrice * l.qty) : null,
  ]);
  return [
    for (final (i, l) in cart.lines.indexed)
      !eligible(l)
          ? null
          : bundled.containsKey(i)
              ? (bundled[i]!.$2 > 0 ? (label: bundled[i]!.$1.name, discount: Discount.amount(bundled[i]!.$2)) : null)
              : _bestBenefit(cart, running, l),
  ];
}

({String label, Discount discount})? _bestBenefit(CartState cart, List<Promotion> running, CartLine l) {
  Promotion? best;
  var promoAmount = 0;
  for (final p in running) {
    final d = p.discountFor(
        productId: l.product.id, categoryId: l.product.categoryId, unitPrice: l.unitPrice, qty: l.qty, basePrice: l.product.price);
    if (d > promoAmount) {
      best = p;
      promoAmount = d;
    }
  }
  final tier = cart.customer?.tier;
  final tierAmount = tier != null && tier.discountBp > 0 ? l.unitPrice * l.qty * tier.discountBp ~/ 10000 : 0;
  if (best != null && promoAmount >= tierAmount) return (label: best.name, discount: Discount.amount(promoAmount));
  if (tierAmount > 0) return (label: 'Diskon member', discount: Discount.percent(tier!.discountBp));
  return null;
}

/// Potongan dari hadiah (untuk rincian keranjang).
int rewardDiscount(CartState cart, PricingResult totals) {
  final reward = cart.reward;
  if (reward == null) return 0;
  if (!reward.isFreeProduct) return totals.orderDiscount;
  final i = cart.lines.indexWhere((l) => l.id == cart.rewardItemId);
  return i >= 0 && i < totals.lineDiscounts.length ? totals.lineDiscounts[i] : 0;
}


/// Perkiraan stempel/poin yang didapat member dari order ini (server menghitung ulang saat bayar).
int loyaltyEarnPreview(CartState cart, Menu menu, PricingResult totals) =>
    _baseEarn(cart, menu, totals) * (cart.customer?.tier?.earnMultiplier ?? 1);

int _baseEarn(CartState cart, Menu menu, PricingResult totals) {
  final p = menu.loyalty;
  if (p == null || cart.customer == null || cart.isEmpty) return 0;
  switch (p.earnMode) {
    case 'per_order':
      return totals.grandTotal >= (p.earnMinOrder ?? 0) ? 1 : 0;
    case 'per_amount':
      final per = p.earnPerAmount ?? 0;
      return per > 0 ? totals.grandTotal ~/ per : 0;
    default:
      var qty = 0;
      for (final l in cart.lines) {
        if (p.categoryIds.isEmpty || p.categoryIds.contains(l.product.categoryId)) {
          qty += l.qty;
          if (cart.reward?.isFreeProduct == true && l.id == cart.rewardItemId) qty -= 1; // porsi gratis
        }
      }
      return qty < 0 ? 0 : qty;
  }
}

class CartController extends Notifier<CartState> {
  @override
  CartState build() => CartState(orderId: _uuid.v4());

  void add(ModifierSelection selection) {
    final chosenIds = selection.chosen.map((m) => m.id).toList();
    // Produk + pilihan yang sama dan belum diberi catatan/diskon → cukup tambah qty.
    final i = state.lines.indexWhere((l) =>
        l.product.id == selection.product.id &&
        l.note == null &&
        l.discount == null &&
        _sameIds(l.modifiers.map((m) => m.id).toList(), chosenIds));

    if (i >= 0) {
      setQty(state.lines[i].id, state.lines[i].qty + 1);
      return;
    }
    state = state.copyWith(lines: [
      ...state.lines,
      CartLine(id: _uuid.v4(), product: selection.product, modifiers: selection.chosen, qty: 1),
    ]);
  }

  void setQty(String lineId, int qty) {
    // Baris hadiah dihapus → hadiah ikut dilepas.
    if (qty <= 0 && lineId == state.rewardItemId) state = state.copyWith(clearReward: true);
    state = state.copyWith(lines: [
      for (final l in state.lines)
        if (l.id != lineId)
          l
        else if (qty > 0)
          l.copyWith(qty: qty.clamp(1, 999)),
    ]);
  }

  void setNote(String lineId, String note) => _update(lineId, (l) => l.copyWith(note: note));

  void setLineDiscount(String lineId, Discount? discount) =>
      _update(lineId, (l) => l.copyWith(discount: discount, clearDiscount: discount == null));

  void setOrderDiscount(Discount? discount) =>
      state = state.copyWith(orderDiscount: discount, clearOrderDiscount: discount == null);

  void setCustomerLabel(String label) => state = state.copyWith(customerLabel: label);

  void setOrderType(String type) => state = state.copyWith(orderType: type);

  void setTableLabel(String label) => state = state.copyWith(tableLabel: label);

  /// Tautkan member. Kolom nama yang masih kosong diisi nama member (tetap bisa diganti, mis. "Meja 5").
  void setCustomer(CartCustomer customer) => state = state.copyWith(
        customer: customer,
        customerLabel: state.customerLabel.trim().isEmpty ? customer.name : null,
      );

  /// Tukar hadiah: gratis produk memakai baris [itemId] (diskon manualnya dilepas); potongan Rp/%
  /// menggantikan diskon order manual.
  void setReward(LoyaltyReward reward, {String? itemId}) {
    state = state.copyWith(
      reward: reward,
      rewardItemId: reward.isFreeProduct ? itemId : null,
      clearOrderDiscount: !reward.isFreeProduct,
      clearVoucher: !reward.isFreeProduct, // hadiah potongan memakai jatah diskon order
      lines: reward.isFreeProduct
          ? [for (final l in state.lines) l.id == itemId ? l.copyWith(clearDiscount: true) : l]
          : null,
    );
  }

  void clearReward() => state = state.copyWith(clearReward: true);

  /// Pakai voucher: menggantikan diskon order manual (tidak bisa digabung).
  void setVoucher(VoucherTerms voucher) => state = state.copyWith(voucher: voucher, clearOrderDiscount: true);

  void clearVoucher() => state = state.copyWith(clearVoucher: true);

  /// Lepas member; label yang masih sama dengan nama member ikut dikosongkan.
  void clearCustomer() {
    final label = state.customerLabel.trim();
    state = state.copyWith(
      clearCustomer: true,
      customerLabel: label == state.customer?.name ? '' : null,
    );
  }

  void markSaved(String number) => state = state.copyWith(number: number);

  /// Semua item saat ini sudah dikirim ke bar/dapur.
  void markTicketed() => state = state.copyWith(ticketed: {for (final l in state.lines) l.id: l.qty});

  /// Mulai order baru (setelah dibayar / disimpan sebagai open bill).
  void clear() => state = CartState(orderId: _uuid.v4());

  /// Muat open bill dari server agar bisa ditambah item / dibayar. Item yang produknya sudah
  /// tidak ada di menu tetap dipertahankan dengan harga & nama snapshot.
  void loadOrder(Map<String, dynamic> order, Menu menu) {
    final lines = <CartLine>[];
    for (final raw in (order['items'] as List).cast<Map<String, dynamic>>()) {
      final product = menu.product(raw['product_id'] as String? ?? '') ??
          MenuProduct(
            id: raw['product_id'] as String? ?? '',
            categoryId: '',
            name: raw['name'] as String,
            price: raw['unit_price'] as int,
            active: false,
            soldOut: false,
            sort: 0,
            modifierGroupIds: const [],
          );
      final modifiers = [
        for (final m in (raw['modifiers'] as List).cast<Map<String, dynamic>>())
          // Tambahan berjumlah (qty > 1) diulang, sama seperti saat dipilih di kasir.
          for (var i = 0; i < (m['qty'] as int? ?? 1); i++)
            MenuModifier(
              id: m['modifier_id'] as String? ?? '',
              name: m['name'] as String,
              priceDelta: m['price_delta'] as int,
              active: true,
            ),
      ];
      lines.add(CartLine(
        id: raw['id'] as String,
        product: product,
        modifiers: modifiers,
        qty: raw['qty'] as int,
        note: raw['note'] as String?,
        discount: raw['discount'] == null ? null : Discount.fromJson(raw['discount'] as Map<String, dynamic>),
      ));
    }

    final customer = order['customer'] as Map<String, dynamic>?;
    final savedReward = order['reward'] as Map<String, dynamic>?;
    LoyaltyReward? reward;
    if (savedReward != null) {
      // Data hadiah lengkap dari menu; hadiah yang kini nonaktif direka ulang dari salinan di order.
      reward = menu.loyalty?.rewards.where((r) => r.id == savedReward['id']).firstOrNull ??
          LoyaltyReward(
            id: savedReward['id'] as String,
            name: savedReward['name'] as String? ?? 'Hadiah',
            cost: savedReward['cost'] as int? ?? 0,
            type: savedReward['item_id'] != null ? 'free_product' : 'amount',
            productId: lines.where((l) => l.id == savedReward['item_id']).firstOrNull?.product.id,
            value: savedReward['discount'] as int? ?? 0,
          );
    }
    state = CartState(
      orderId: order['id'] as String,
      createdAt: DateTime.tryParse(order['created_at'] as String? ?? '')?.toUtc(),
      orderType: order['order_type'] as String?,
      tableLabel: order['table_label'] as String? ?? '',
      lines: lines,
      customerLabel: order['customer_label'] as String? ?? '',
      customer: customer == null
          ? null
          : CartCustomer(
              id: customer['id'] as String,
              code: customer['code'] as String,
              name: customer['name'] as String,
              // Salinan tingkat saat order disimpan; server memeriksa ulang saat disimpan lagi.
              tier: order['tier'] == null
                  ? null
                  : MemberTier.fromJson({
                      ...order['tier'] as Map<String, dynamic>,
                      ...?menu.memberTiers.where((t) => t.id == (order['tier'] as Map)['id']).map((t) => {'color': t.color}).firstOrNull,
                    }),
            ),
      reward: reward,
      rewardItemId: savedReward?['item_id'] as String?,
      // Voucher tersimpan: potongan dari salinan di order (server menghitung ulang saat disimpan lagi).
      voucher: order['voucher'] is Map
          ? VoucherTerms(
              code: (order['voucher'] as Map)['code'] as String,
              type: 'amount',
              value: (order['voucher'] as Map)['discount'] as int,
            )
          : null,
      // Open bill yang dimuat ulang: item lamanya sudah dicetak ke bar/dapur saat disimpan.
      ticketed: {for (final l in lines) l.id: l.qty},
      orderDiscount: order['order_discount'] == null
          ? null
          : Discount.fromJson(order['order_discount'] as Map<String, dynamic>),
      number: order['number'] as String,
    );
  }

  void _update(String lineId, CartLine Function(CartLine) f) =>
      state = state.copyWith(lines: [for (final l in state.lines) l.id == lineId ? f(l) : l]);

  /// Sama persis termasuk jumlah (Extra shot x1 ≠ x2), tanpa peduli urutan.
  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final x = [...a]..sort();
    final y = [...b]..sort();
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}
