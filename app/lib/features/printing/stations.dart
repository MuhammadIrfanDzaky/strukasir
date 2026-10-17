import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../cart/cart_controller.dart';
import '../menu/modifier_selection.dart' show modifierSummary;
import 'receipt_format.dart';

/// Stasiun tiket (Bar, Dapur, …) di tablet ini: printer & kategori produk yang dicetak ke sana.
class TicketStation {
  const TicketStation({required this.name, this.printerMac, this.printerName, this.categoryIds = const [], this.copies = 1});

  factory TicketStation.fromJson(Map<String, dynamic> j) => TicketStation(
        name: j['name'] as String,
        printerMac: j['printer_mac'] as String?,
        printerName: j['printer_name'] as String?,
        categoryIds: ((j['category_ids'] as List?) ?? const []).cast<String>(),
        copies: j['copies'] as int? ?? 1,
      );

  final String name;

  /// Null = printer struk yang sama.
  final String? printerMac;
  final String? printerName;

  /// Kategori yang dicetak di stasiun ini; kosong = semua produk.
  final List<String> categoryIds;
  final int copies;

  bool takes(String categoryId) => categoryIds.isEmpty || categoryIds.contains(categoryId);

  Map<String, dynamic> toJson() => {
        'name': name,
        'printer_mac': printerMac,
        'printer_name': printerName,
        'category_ids': categoryIds,
        'copies': copies,
      };
}

final stationsProvider = AsyncNotifierProvider<StationsController, List<TicketStation>>(StationsController.new);

/// Disimpan di tablet (printer & tata letak bar beda tiap tablet).
class StationsController extends AsyncNotifier<List<TicketStation>> {
  static const _storage = FlutterSecureStorage();
  static const _key = 'ticket_stations';

  @override
  Future<List<TicketStation>> build() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(TicketStation.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<TicketStation> stations) async {
    await _storage.write(key: _key, value: jsonEncode([for (final s in stations) s.toJson()]));
    state = AsyncData(stations);
  }
}

/// Satu baris tiket: jumlah yang perlu dibuat, nama, pilihan, catatan.
class TicketItem {
  const TicketItem({required this.qty, required this.name, required this.categoryId, this.options = '', this.note});

  final int qty;
  final String name;
  final String categoryId;
  final String options;
  final String? note;
}

/// Item yang belum pernah dikirim ke bar/dapur: baris baru, atau tambahan qty di open bill.
List<TicketItem> pendingTicketItems(CartState cart) => [
      for (final l in cart.lines)
        if (l.qty > (cart.ticketed[l.id] ?? 0))
          TicketItem(
            qty: l.qty - (cart.ticketed[l.id] ?? 0),
            name: l.product.name,
            categoryId: l.product.categoryId,
            options: l.modifiers.isEmpty ? '' : modifierSummary(l.modifiers, times: 'x'), // huruf x: aman di printer thermal
            note: l.note,
          ),
    ];

/// Item order (JSON server) untuk cetak ulang tiket lengkap.
List<TicketItem> orderTicketItems(Map<String, dynamic> order, String Function(String productId) categoryOf) => [
      for (final i in (order['items'] as List).cast<Map<String, dynamic>>())
        TicketItem(
          qty: i['qty'] as int,
          name: i['name'] as String,
          categoryId: categoryOf(i['product_id'] as String? ?? ''),
          options: (i['modifiers'] as List)
              .cast<Map<String, dynamic>>()
              .map((m) => (m['qty'] as int? ?? 1) > 1 ? '${m['name']} x${m['qty']}' : '${m['name']}')
              .join(', '),
          note: i['note'] as String?,
        ),
    ];

/// Tiket untuk satu stasiun (tanpa harga): huruf tebal supaya terbaca dari jauh.
List<PrintLine> kitchenTicket({
  required String station,
  required String number,
  required String? label,
  required List<TicketItem> items,
  required DateTime at,
  bool addition = false,
  bool reprint = false,
  String? orderType,
}) {
  final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  return [
    PrintLine(center(station.toUpperCase()), bold: true),
    if (addition) PrintLine(center('*** TAMBAHAN ***'), bold: true),
    if (reprint) PrintLine(center('(cetak ulang)')),
    PrintLine(divider()),
    PrintLine(leftRight(number, time).first, bold: true),
    // Bar/dapur perlu tahu: dibungkus atau diantar ke meja berapa.
    if (orderType != null) ...wrap(orderType).map((l) => PrintLine(l, bold: true)),
    if (label != null && label.trim().isNotEmpty) ...wrap(label.trim()).map((l) => PrintLine(l, bold: true)),
    PrintLine(divider()),
    for (final i in items) ...[
      ...wrap('${i.qty}x ${i.name}').map((l) => PrintLine(l, bold: true)),
      if (i.options.isNotEmpty) ...wrap('   ${i.options}').map(PrintLine.new),
      if (i.note != null && i.note!.trim().isNotEmpty) ...wrap('   * ${i.note!.trim()}').map((l) => PrintLine(l, bold: true)),
    ],
    PrintLine(divider()),
  ];
}
