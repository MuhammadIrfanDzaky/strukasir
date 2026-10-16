import '../../core/money.dart';

/// Tipe promo (urutan = urutan pilihan di form) → nama.
const promotionTypes = <String, String>{
  'percent': 'Diskon %',
  'amount': 'Potongan Rp per item',
  'price': 'Harga spesial',
  'min_qty': 'Beli banyak lebih hemat',
  'bogo': 'Beli X gratis Y',
  'bundle': 'Paket bundling',
};

/// Rentang jam promo "HH:mm"–"HH:mm" (jam selesai tidak termasuk; boleh melewati tengah malam).
typedef PromoWindow = ({String start, String end});

/// Isi paket bundling.
typedef BundleItem = ({String productId, int qty});

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
    this.times,
    this.bundleItems = const [],
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
        times: j['times'] is List
            ? [for (final w in (j['times'] as List).cast<Map<String, dynamic>>()) (start: w['start'] as String, end: w['end'] as String)]
            // Cache menu dari server lama: satu rentang start_time/end_time.
            : j['start_time'] is String && j['end_time'] is String
                ? [(start: j['start_time'] as String, end: j['end_time'] as String)]
                : null,
        bundleItems: [
          for (final b in ((j['bundle_items'] as List?) ?? const []).cast<Map<String, dynamic>>())
            (productId: b['product_id'] as String, qty: b['qty'] as int),
        ],
        startsOn: j['starts_on'] as String?,
        endsOn: j['ends_on'] as String?,
        active: j['active'] as bool? ?? true,
      );

  final String id;
  final String name;

  /// percent (value = bp) | amount (Rp per item) | price (harga spesial Rp) | min_qty (beli ≥ buyQty → value bp)
  /// | bogo (beli X gratis Y) | bundle (bundleItems dijual seharga value)
  final String type;
  final int value;
  final int buyQty;
  final int freeQty;

  /// all | categories | products
  final String scope;
  final List<String> targetIds;

  /// ISO 1 = Senin … 7 = Minggu; null = setiap hari.
  final List<int>? days;

  /// Rentang jam; null = sepanjang hari.
  final List<PromoWindow>? times;

  /// Isi paket (tipe bundle).
  final List<BundleItem> bundleItems;

  /// "YYYY-MM-DD"
  final String? startsOn;
  final String? endsOn;
  final bool active;

  bool runsAt(DateTime at) {
    final date = _ymd(at);
    if ((startsOn != null && date.compareTo(startsOn!) < 0) || (endsOn != null && date.compareTo(endsOn!) > 0)) return false;
    if (days != null && !days!.contains(at.weekday)) return false;
    if (times == null || times!.isEmpty) return true;
    final t = '${_pad(at.hour)}:${_pad(at.minute)}';
    // Melewati tengah malam (mis. 22:00–02:00).
    return times!.any((w) => w.start.compareTo(w.end) <= 0
        ? t.compareTo(w.start) >= 0 && t.compareTo(w.end) < 0
        : t.compareTo(w.start) >= 0 || t.compareTo(w.end) < 0);
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
      'price' => _min((basePrice - value < 0 ? 0 : basePrice - value) * qty, gross),
      'min_qty' => qty >= buyQty ? gross * value ~/ 10000 : 0,
      'bogo' => _min((qty ~/ (buyQty + freeQty)) * freeQty * basePrice, gross),
      _ => 0, // bundle: lintas baris (bundleDiscounts)
    };
  }

  /// "Diskon 20%", "Potongan Rp 2.000/item", "Beli 2 gratis 1", "Paket Rp 25.000".
  String get effect => switch (type) {
        'percent' => 'Diskon ${percentBp(value)}',
        'amount' => 'Potongan ${rp(value)}/item',
        'price' => 'Harga spesial ${rp(value)}',
        'min_qty' => 'Beli $buyQty+ diskon ${percentBp(value)}',
        'bogo' => 'Beli $buyQty gratis $freeQty',
        _ => 'Paket ${rp(value)}',
      };

  /// "Rab · 14:00–17:00 · s/d 31/12/2026"
  String get schedule {
    const names = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return [
      days == null ? 'Setiap hari' : (days!.toList()..sort()).map((d) => names[d - 1]).join(', '),
      if (times != null && times!.isNotEmpty) times!.map((w) => '${w.start}–${w.end}').join(', '),
      if (startsOn != null) 'mulai ${_dmy(startsOn!)}',
      if (endsOn != null) 's/d ${_dmy(endsOn!)}',
    ].join(' · ');
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
  static String _ymd(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
  static String _dmy(String ymd) => '${ymd.substring(8, 10)}/${ymd.substring(5, 7)}/${ymd.substring(0, 4)}';
  static int _min(int a, int b) => a < b ? a : b;
}

/// Baris keranjang yang boleh dapat promo (tanpa diskon manual & bukan hadiah).
typedef PromoLine = ({String productId, int price, int qty, int gross});

/// Paket bundling lintas baris = PromotionService::bundles di server. Untuk tiap paket (urut nama):
/// set = min(⌊qty tersedia / qty di paket⌋); potongan = set × (harga normal − harga paket) dibagi per isi
/// sebanding harga normalnya (sisa ke isi terakhir), lalu ke baris produk itu berurutan (maks. harga baris).
/// Baris yang terpakai paket tidak ikut paket lain / promo per baris / diskon member.
/// [lines]: null = baris tidak boleh dapat promo. Hasil: indeks baris → (promo, potongan).
Map<int, (Promotion, int)> bundleDiscounts(List<Promotion> running, List<PromoLine?> lines) {
  final used = <int, (Promotion, int)>{};
  List<int> free(String productId) => [
        for (var i = 0; i < lines.length; i++)
          if (lines[i] != null && lines[i]!.productId == productId && !used.containsKey(i)) i,
      ];
  for (final p in running) {
    if (p.type != 'bundle' || p.bundleItems.isEmpty) continue;
    var sets = 1 << 30;
    var normal = 0;
    for (final part in p.bundleItems) {
      final m = free(part.productId);
      final qty = m.fold(0, (s, i) => s + lines[i]!.qty);
      sets = _minInt(sets, qty ~/ part.qty);
      normal += part.qty * (m.isEmpty ? 0 : lines[m.first]!.price);
    }
    if (sets < 1 || normal <= p.value) continue;
    final discount = sets * (normal - p.value);
    var left = discount;
    for (var j = 0; j < p.bundleItems.length; j++) {
      final part = p.bundleItems[j];
      final m = free(part.productId);
      final price = lines[m.first]!.price;
      var share = j == p.bundleItems.length - 1 ? left : discount * part.qty * price ~/ normal;
      left -= share;
      var units = sets * part.qty;
      for (final i in m) {
        if (units <= 0) break;
        units -= lines[i]!.qty;
        final amount = _minInt(share, lines[i]!.gross);
        share -= amount;
        used[i] = (p, amount);
      }
    }
  }
  return used;
}

int _minInt(int a, int b) => a < b ? a : b;

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
