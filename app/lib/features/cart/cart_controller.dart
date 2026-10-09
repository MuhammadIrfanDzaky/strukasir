import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../menu/menu_controller.dart';
import '../menu/menu_models.dart';
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
  const CartCustomer({required this.id, required this.code, required this.name, this.phone, this.visits, this.note});

  final String id;
  final String code;
  final String name;

  /// Tersamar untuk kasir (0812****7890).
  final String? phone;
  final int? visits;

  /// Catatan pelanggan (alergi, selera) — ditampilkan ke kasir.
  final String? note;
}

class CartState {
  const CartState({
    required this.orderId,
    this.lines = const [],
    this.customerLabel = '',
    this.customer,
    this.orderDiscount,
    this.number,
  });

  /// UUID order dibuat di tablet = idempotency key. Kirim ulang aman.
  final String orderId;
  final List<CartLine> lines;
  final String customerLabel;

  /// Pelanggan / member (opsional, fitur `customers`).
  final CartCustomer? customer;
  final Discount? orderDiscount;

  /// Nomor dari server bila order sudah pernah disimpan (open bill).
  final String? number;

  bool get isEmpty => lines.isEmpty;
  bool get isSaved => number != null;
  int get itemCount => lines.fold(0, (s, l) => s + l.qty);

  CartState copyWith({
    List<CartLine>? lines,
    String? customerLabel,
    CartCustomer? customer,
    bool clearCustomer = false,
    Discount? orderDiscount,
    bool clearOrderDiscount = false,
    String? number,
  }) =>
      CartState(
        orderId: orderId,
        lines: lines ?? this.lines,
        customerLabel: customerLabel ?? this.customerLabel,
        customer: clearCustomer ? null : (customer ?? this.customer),
        orderDiscount: clearOrderDiscount ? null : (orderDiscount ?? this.orderDiscount),
        number: number ?? this.number,
      );

  Map<String, dynamic> toJson(int expectedTotal) => {
        'customer_label': customerLabel.trim().isEmpty ? null : customerLabel.trim(),
        'customer_id': customer?.id,
        'client_created_at': DateTime.now().toUtc().toIso8601String(),
        'expected_total': expectedTotal,
        'items': lines.map((l) => l.toJson()).toList(),
        'order_discount': orderDiscount?.toJson(),
      };
}

final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);

/// Total keranjang dihitung di tablet dengan aturan yang sama dengan server.
final cartTotalsProvider = Provider<PricingResult>((ref) {
  final cart = ref.watch(cartProvider);
  final menu = ref.watch(menuProvider).value?.menu;
  if (menu == null || cart.isEmpty) return PricingResult.empty;
  try {
    return calculatePrice(
      [for (final l in cart.lines) PricingLine(unitPrice: l.unitPrice, qty: l.qty, discount: l.discount)],
      cart.orderDiscount,
      menu.pricing,
    );
  } on PricingException {
    return PricingResult.empty;
  }
});

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

  /// Tautkan member. Kolom nama yang masih kosong diisi nama member (tetap bisa diganti, mis. "Meja 5").
  void setCustomer(CartCustomer customer) => state = state.copyWith(
        customer: customer,
        customerLabel: state.customerLabel.trim().isEmpty ? customer.name : null,
      );

  /// Lepas member; label yang masih sama dengan nama member ikut dikosongkan.
  void clearCustomer() {
    final label = state.customerLabel.trim();
    state = state.copyWith(
      clearCustomer: true,
      customerLabel: label == state.customer?.name ? '' : null,
    );
  }

  void markSaved(String number) => state = state.copyWith(number: number);

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
    state = CartState(
      orderId: order['id'] as String,
      lines: lines,
      customerLabel: order['customer_label'] as String? ?? '',
      customer: customer == null
          ? null
          : CartCustomer(id: customer['id'] as String, code: customer['code'] as String, name: customer['name'] as String),
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
