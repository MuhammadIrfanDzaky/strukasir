/// Layout struk thermal 58mm (32 karakter/baris, Font A) dari data order server (OrderResource).
/// Fungsi murni → diuji di test/receipt_format_test.dart tanpa printer.
library;

import '../../core/money.dart';

const int kLineWidth = 32;

List<String> wrap(String text, {int width = kLineWidth}) {
  final lines = <String>[];
  var current = '';
  for (final word in text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
    var w = word;
    while (w.length > width) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      lines.add(w.substring(0, width));
      w = w.substring(width);
    }
    if (current.isEmpty) {
      current = w;
    } else if (current.length + 1 + w.length <= width) {
      current = '$current $w';
    } else {
      lines.add(current);
      current = w;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.isEmpty ? [''] : lines;
}

/// Kiri & kanan dalam satu baris; bila tidak muat, teks kiri di-wrap dan angka di baris terakhir.
List<String> leftRight(String left, String right, {int width = kLineWidth}) {
  final room = width - right.length - 1;
  final leftLines = wrap(left, width: room < 8 ? width : room);
  final last = leftLines.removeLast();
  if (last.length + 1 + right.length <= width) {
    return [...leftLines, last.padRight(width - right.length) + right];
  }
  return [...leftLines, last, right.padLeft(width)];
}

String center(String text, {int width = kLineWidth}) {
  if (text.length >= width) return text.substring(0, width);
  final pad = (width - text.length) ~/ 2;
  return (' ' * pad + text).padRight(width);
}

String divider([String ch = '-']) => ch * kLineWidth;

String _time(String iso) {
  final d = DateTime.parse(iso).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

const _methodLabel = {'cash': 'Tunai', 'debit': 'Debit', 'qris': 'QRIS'};

/// Struk pelanggan. `paid=false` → bill "BELUM DIBAYAR" (tanpa baris pembayaran).
List<String> customerReceipt(Map<String, dynamic> order) {
  final paid = order['status'] == 'paid';
  final receipt = order['receipt'] as Map<String, dynamic>? ?? const {};
  final out = <String>[
    center((receipt['name'] as String?) ?? ''),
    if ((receipt['header'] as String?)?.isNotEmpty ?? false)
      for (final l in (receipt['header'] as String).split('\n')) ...wrap(l).map(center),
    divider(),
    'No   : ${order['number']}',
    'Waktu: ${_time((order['paid_at'] ?? order['created_at']) as String)}',
    if (order['cashier'] != null) 'Kasir: ${order['cashier']}',
    if ((order['customer_label'] as String?)?.isNotEmpty ?? false) ...wrap('Nama : ${order['customer_label']}'),
    divider(),
  ];

  for (final item in (order['items'] as List).cast<Map<String, dynamic>>()) {
    final qty = item['qty'] as int;
    final unit = (item['unit_price'] as int) + (item['modifiers_total'] as int);
    out.addAll(wrap(item['name'] as String));
    for (final m in (item['modifiers'] as List).cast<Map<String, dynamic>>()) {
      out.addAll(wrap('  + ${m['name']}'));
    }
    if (item['note'] != null) out.addAll(wrap('  * ${item['note']}'));
    out.addAll(leftRight('  $qty x ${rupiah(unit)}', rupiah(qty * unit)));
    final disc = item['discount_total'] as int;
    if (disc > 0) out.addAll(leftRight('  Diskon', '-${rupiah(disc)}'));
  }

  final itemDiscounts =
      (order['items'] as List).cast<Map<String, dynamic>>().fold<int>(0, (s, i) => s + (i['discount_total'] as int));
  final orderDiscount = (order['discount_total'] as int) - itemDiscounts;

  out.add(divider());
  out.addAll(leftRight('Subtotal', rupiah(order['subtotal'] as int)));
  if (orderDiscount > 0) out.addAll(leftRight('Diskon', '-${rupiah(orderDiscount)}'));
  if ((order['service_total'] as int) > 0) out.addAll(leftRight('Service', rupiah(order['service_total'] as int)));
  if ((order['tax_total'] as int) > 0) out.addAll(leftRight('Pajak', rupiah(order['tax_total'] as int)));
  if ((order['rounding'] as int) != 0) out.addAll(leftRight('Pembulatan', rupiah(order['rounding'] as int)));
  out.addAll(leftRight('TOTAL', 'Rp ${rupiah(order['grand_total'] as int)}'));

  if (paid) {
    for (final p in (order['payments'] as List).cast<Map<String, dynamic>>()) {
      final label = _methodLabel[p['method']] ?? '${p['method']}';
      out.addAll(leftRight(label, rupiah((p['tendered'] ?? p['amount']) as int)));
    }
    if ((order['change_total'] as int) > 0) out.addAll(leftRight('Kembali', rupiah(order['change_total'] as int)));
  }

  out.add(divider());
  if (paid) {
    out.add(center('LUNAS'));
    if ((receipt['footer'] as String?)?.isNotEmpty ?? false) {
      for (final l in (receipt['footer'] as String).split('\n')) {
        out.addAll(wrap(l).map(center));
      }
    }
  } else {
    out.add(center('*** BELUM DIBAYAR ***'));
  }
  return out;
}

/// Laporan tutup shift (dari respons POST /shifts/close).
List<String> shiftReport(Map<String, dynamic> shift) {
  final s = shift['summary'] as Map<String, dynamic>;
  final byMethod = s['by_method'] as Map<String, dynamic>;
  final diff = shift['difference'] as int;
  return [
    center('LAPORAN SHIFT'),
    divider(),
    'Buka : ${_time(shift['opened_at'] as String)}',
    ...wrap('       ${shift['opened_by'] ?? ''}'),
    'Tutup: ${_time(shift['closed_at'] as String)}',
    ...wrap('       ${shift['closed_by'] ?? ''}'),
    divider(),
    ...leftRight('Modal awal', rupiah(s['opening_cash'] as int)),
    ...leftRight('Tunai masuk', rupiah(s['cash_in'] as int)),
    if ((s['cash_refund'] as int) > 0) ...leftRight('Refund tunai', '-${rupiah(s['cash_refund'] as int)}'),
    ...leftRight('Kas seharusnya', rupiah(shift['expected_cash'] as int)),
    ...leftRight('Kas dihitung', rupiah(shift['counted_cash'] as int)),
    ...leftRight(diff == 0 ? 'Selisih' : (diff > 0 ? 'LEBIH' : 'KURANG'), rupiah(diff.abs())),
    divider(),
    ...leftRight('Debit', rupiah(byMethod['debit'] as int)),
    ...leftRight('QRIS', rupiah(byMethod['qris'] as int)),
    ...leftRight('Order lunas', '${s['paid_orders']}'),
    if ((s['refunds'] as int) > 0) ...leftRight('Order di-refund', '${s['refunds']}'),
    if ((shift['note'] as String?)?.isNotEmpty ?? false) ...wrap('Catatan: ${shift['note']}'),
    divider(),
  ];
}

/// Checker untuk barista: tanpa harga; item, pilihan, dan catatan.
List<String> checker(Map<String, dynamic> order) {
  final out = <String>[
    center('CHECKER'),
    'No  : ${order['number']}',
    if ((order['customer_label'] as String?)?.isNotEmpty ?? false) ...wrap('Nama: ${order['customer_label']}'),
    'Jam : ${_time(order['created_at'] as String).substring(11)}',
    divider(),
  ];
  for (final item in (order['items'] as List).cast<Map<String, dynamic>>()) {
    out.addAll(wrap('${item['qty']}x ${item['name']}'));
    for (final m in (item['modifiers'] as List).cast<Map<String, dynamic>>()) {
      out.addAll(wrap('   + ${m['name']}'));
    }
    if (item['note'] != null) out.addAll(wrap('   * ${item['note']}'));
  }
  out.add(divider());
  return out;
}
