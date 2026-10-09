import '../../core/money.dart';

/// Promo otomatis (bagian `promotions` dari GET /menu). Rumus potongan = PromotionService di server.
class Promotion {
  const Promotion({
    required this.id,
    required this.name,
    required this.type,
    this.value = 0,
    this.buyQty = 0,
    this.freeQty = 0,
    this.scope = 'all',
    this.targetIds = const [],
    this.days,
    this.startTime,
    this.endTime,
    this.startsOn,
    this.endsOn,
    this.active = true,
  });

  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] as String,
        value: j['value'] as int? ?? 0,
        buyQty: j['buy_qty'] as int? ?? 0,
        freeQty: j['free_qty'] as int? ?? 0,
        scope: j['scope'] as String? ?? 'all',
        targetIds: ((j['target_ids'] as List?) ?? const []).cast<String>(),
        days: (j['days'] as List?)?.cast<int>(),
        startTime: j['start_time'] as String?,
        endTime: j['end_time'] as String?,
        startsOn: j['starts_on'] as String?,
        endsOn: j['ends_on'] as String?,
        active: j['active'] as bool? ?? true,
      );

  final String id;
  final String name;

  /// percent (bp) | amount (Rp per item) | bogo (beli X gratis Y)
  final String type;
  final int value;
  final int buyQty;
  final int freeQty;

  /// all | categories | products
  final String scope;
  final List<String> targetIds;

  /// ISO 1 = Senin … 7 = Minggu; null = setiap hari.
  final List<int>? days;

  /// "HH:mm"; null = sepanjang hari.
  final String? startTime;
  final String? endTime;

  /// "YYYY-MM-DD"
  final String? startsOn;
  final String? endsOn;
  final bool active;

  bool runsAt(DateTime at) {
    final date = _ymd(at);
    if ((startsOn != null && date.compareTo(startsOn!) < 0) || (endsOn != null && date.compareTo(endsOn!) > 0)) return false;
    if (days != null && !days!.contains(at.weekday)) return false;
    if (startTime == null || endTime == null) return true;
    final t = '${_pad(at.hour)}:${_pad(at.minute)}:${_pad(at.second)}';
    final start = '$startTime:00';
    final end = '$endTime:00';
    // Melewati tengah malam (mis. 22:00–02:00).
    return start.compareTo(end) <= 0
        ? t.compareTo(start) >= 0 && t.compareTo(end) < 0
        : t.compareTo(start) >= 0 || t.compareTo(end) < 0;
  }

  bool covers(String productId, String categoryId) => switch (scope) {
        'categories' => targetIds.contains(categoryId),
        'products' => targetIds.contains(productId),
        _ => true,
      };

  /// Potongan untuk satu baris (harga satuan termasuk tambahan × qty); [basePrice] = harga dasar produk.
  int discountFor({required String productId, required String categoryId, required int unitPrice, required int qty, required int basePrice}) {
    if (!covers(productId, categoryId)) return 0;
    final gross = unitPrice * qty;
    return switch (type) {
      'percent' => gross * value ~/ 10000,
      'amount' => value * qty < gross ? value * qty : gross,
      _ => _min((qty ~/ (buyQty + freeQty)) * freeQty * basePrice, gross),
    };
  }

  /// "Diskon 20%", "Potongan Rp 2.000/item", "Beli 2 gratis 1".
  String get effect => switch (type) {
        'percent' => 'Diskon ${percentBp(value)}',
        'amount' => 'Potongan ${rp(value)}/item',
        _ => 'Beli $buyQty gratis $freeQty',
      };

  /// "Rab · 14:00–17:00 · s/d 31/12/2026"
  String get schedule {
    const names = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return [
      days == null ? 'Setiap hari' : (days!.toList()..sort()).map((d) => names[d - 1]).join(', '),
      if (startTime != null) '$startTime–$endTime',
      if (startsOn != null) 'mulai ${_dmy(startsOn!)}',
      if (endsOn != null) 's/d ${_dmy(endsOn!)}',
    ].join(' · ');
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
  static String _ymd(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
  static String _dmy(String ymd) => '${ymd.substring(8, 10)}/${ymd.substring(5, 7)}/${ymd.substring(0, 4)}';
  static int _min(int a, int b) => a < b ? a : b;
}

/// Syarat voucher (GET /vouchers/check) untuk menghitung total di tablet.
class VoucherTerms {
  const VoucherTerms({required this.code, required this.type, required this.value, this.maxDiscount, this.minSpend = 0});

  factory VoucherTerms.fromJson(Map<String, dynamic> j) => VoucherTerms(
        code: j['code'] as String,
        type: j['type'] as String,
        value: j['value'] as int,
        maxDiscount: j['max_discount'] as int?,
        minSpend: j['min_spend'] as int? ?? 0,
      );

  final String code;
  final String type;
  final int value;
  final int? maxDiscount;
  final int minSpend;

  /// Potongan dari subtotal; 0 bila di bawah minimal belanja (server menolak dengan pesan jelas).
  int discountFor(int subtotal) {
    if (subtotal < minSpend) return 0;
    var d = type == 'percent' ? subtotal * value ~/ 10000 : value;
    if (maxDiscount != null && d > maxDiscount!) d = maxDiscount!;
    return d < subtotal ? d : subtotal;
  }

  String get effect => type == 'percent'
      ? 'Diskon ${percentBp(value)}${maxDiscount == null ? '' : ' (maks. ${rp(maxDiscount!)})'}'
      : 'Potongan ${rp(value)}';
}
