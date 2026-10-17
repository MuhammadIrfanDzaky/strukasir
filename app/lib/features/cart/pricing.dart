/// Cerminan `App\Support\Pricing\PricingService` (backend). Keduanya diuji dengan fixture yang sama
/// (docs/pricing-fixtures.json), jadi total di tablet = total yang dihitung server.
///
/// Urutan: baris (diskon item) → subtotal → diskon order → service → pajak → pembulatan.
/// Harga "termasuk pajak/service" (terpisah per kedai): bagian itu dihitung mundur dan tidak menambah total.
library;

class Discount {
  const Discount.amount(this.value) : type = DiscountType.amount;
  const Discount.percent(this.value) : type = DiscountType.percent; // basis poin: 1000 = 10%

  factory Discount.fromJson(Map<String, dynamic> j) => j['type'] == 'percent'
      ? Discount.percent(j['value'] as int)
      : Discount.amount(j['value'] as int);

  final DiscountType type;
  final int value;

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};
}

enum DiscountType { amount, percent }

class PricingSettings {
  const PricingSettings({
    this.serviceBp = 0,
    this.taxBp = 0,
    this.roundingUnit = 0,
    this.serviceInclusive = false,
    this.taxInclusive = false,
  });

  factory PricingSettings.fromJson(Map<String, dynamic> j) => PricingSettings(
        serviceBp: j['service_bp'] as int,
        taxBp: j['tax_bp'] as int,
        roundingUnit: j['rounding_unit'] as int,
        serviceInclusive: j['service_inclusive'] as bool? ?? false,
        taxInclusive: j['tax_inclusive'] as bool? ?? false,
      );

  final int serviceBp;
  final int taxBp;
  final int roundingUnit;

  /// Pesanan takeaway: tanpa service charge (sama dengan server).
  PricingSettings withoutService() => PricingSettings(
      taxBp: taxBp, roundingUnit: roundingUnit, serviceInclusive: serviceInclusive, taxInclusive: taxInclusive);

  /// Harga di menu sudah termasuk service / pajak.
  final bool serviceInclusive;
  final bool taxInclusive;
}

class PricingLine {
  const PricingLine({required this.unitPrice, required this.qty, this.discount});

  final int unitPrice;
  final int qty;
  final Discount? discount;

  int get gross => unitPrice * qty;
}

class PricingResult {
  const PricingResult({
    required this.lines,
    required this.lineDiscounts,
    required this.subtotal,
    required this.itemDiscountTotal,
    required this.orderDiscount,
    required this.serviceTotal,
    required this.taxTotal,
    required this.rounding,
    required this.grandTotal,
  });

  final List<int> lines;
  final List<int> lineDiscounts;
  final int subtotal;
  final int itemDiscountTotal;
  final int orderDiscount;
  final int serviceTotal;
  final int taxTotal;
  final int rounding;
  final int grandTotal;

  int get discountTotal => itemDiscountTotal + orderDiscount;

  static const empty = PricingResult(
    lines: [], lineDiscounts: [], subtotal: 0, itemDiscountTotal: 0, orderDiscount: 0,
    serviceTotal: 0, taxTotal: 0, rounding: 0, grandTotal: 0,
  );

  Map<String, dynamic> toJson() => {
        'lines': lines,
        'subtotal': subtotal,
        'item_discount_total': itemDiscountTotal,
        'order_discount': orderDiscount,
        'discount_total': discountTotal,
        'service_total': serviceTotal,
        'tax_total': taxTotal,
        'rounding': rounding,
        'grand_total': grandTotal,
      };
}

class PricingException implements Exception {
  PricingException(this.message);

  final String message;

  @override
  String toString() => message;
}

PricingResult calculatePrice(List<PricingLine> items, Discount? orderDiscount, PricingSettings s) {
  final lines = <int>[];
  final lineDiscounts = <int>[];

  for (final item in items) {
    if (item.qty < 1 || item.unitPrice < 0) throw PricingException('Qty/harga tidak valid.');
    final d = _discount(item.gross, item.discount);
    lineDiscounts.add(d);
    lines.add(item.gross - d);
  }

  final subtotal = lines.fold(0, (a, b) => a + b);
  final orderDisc = _discount(subtotal, orderDiscount);
  final base = subtotal - orderDisc;

  // Sama persis dengan PricingService::serviceAndTax (lihat docs/pricing-fixtures.json).
  final taxIncluded = s.taxInclusive ? _halfUp(base * s.taxBp, 10000 + s.taxBp) : 0;
  final afterTax = base - taxIncluded;
  final serviceIncluded = s.serviceInclusive ? _halfUp(afterTax * s.serviceBp, 10000 + s.serviceBp) : 0;
  final serviceAdded = s.serviceInclusive ? 0 : _halfUp(afterTax * s.serviceBp, 10000);
  final taxAdded = s.taxInclusive
      ? _halfUp(serviceAdded * s.taxBp, 10000)
      : _halfUp((afterTax + serviceAdded) * s.taxBp, 10000);
  final service = serviceIncluded + serviceAdded;
  final tax = taxIncluded + taxAdded;
  final beforeRounding = base + serviceAdded + taxAdded;
  final grand = s.roundingUnit > 0
      ? _halfUp(beforeRounding, s.roundingUnit) * s.roundingUnit
      : beforeRounding;

  return PricingResult(
    lines: lines,
    lineDiscounts: lineDiscounts,
    subtotal: subtotal,
    itemDiscountTotal: lineDiscounts.fold(0, (a, b) => a + b),
    orderDiscount: orderDisc,
    serviceTotal: service,
    taxTotal: tax,
    rounding: grand - beforeRounding,
    grandTotal: grand,
  );
}

int _discount(int amount, Discount? d) {
  if (d == null) return 0;
  return switch (d.type) {
    DiscountType.percent when d.value >= 0 && d.value <= 10000 => amount * d.value ~/ 10000,
    DiscountType.percent => throw PricingException('Diskon persen harus 0–100%.'),
    DiscountType.amount when d.value >= 0 && d.value <= amount => d.value,
    DiscountType.amount => throw PricingException('Diskon melebihi harga.'),
  };
}

/// Pembagian dengan pembulatan setengah ke atas (bilangan non-negatif), sama dengan PHP.
int _halfUp(int numerator, int denominator) => (2 * numerator + denominator) ~/ (2 * denominator);
