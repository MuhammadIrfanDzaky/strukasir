/// Layout struk thermal 58mm (32 karakter/baris, Font A) dari data order server (OrderResource).
/// Fungsi murni → diuji di test/receipt_format_test.dart tanpa printer.
library;

import '../../core/money.dart';

const int kLineWidth = 32;

/// Bungkus teks per kata. Spasi di awal (indentasi) dipertahankan di setiap baris hasil.
List<String> wrap(String text, {int width = kLineWidth}) {
  final indent = RegExp(r'^ *').stringMatch(text)!;
  if (indent.isNotEmpty && indent.length <= width ~/ 4) {
    return [for (final l in wrap(text.substring(indent.length), width: width - indent.length)) '$indent$l'];
  }
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

const _methodLabel = {'cash': 'cash', 'debit': 'debit', 'qris': 'qris'};

/// Satu baris cetak (sudah ≤ 32 karakter). `bold` = huruf tebal ESC/POS (lebar tetap sama).
class PrintLine {
  const PrintLine(this.text, {this.bold = false});

  final String text;
  final bool bold;

  @override
  String toString() => text;
}

List<PrintLine> _plain(Iterable<String> lines) => [for (final l in lines) PrintLine(l)];
List<PrintLine> _bold(Iterable<String> lines) => [for (final l in lines) PrintLine(l, bold: true)];

/// Struk pelanggan, mengikuti format struk BerryBrew: identitas kedai, Date/Cashier/Customer/
/// Transaction No, item (nama tebal + pilihan), ringkasan, pembayaran, lalu pesan penutup.
/// Logo (bila ada) dicetak printer di atas baris pertama. `paid=false` → bill "BELUM DIBAYAR".
List<PrintLine> customerReceipt(Map<String, dynamic> order) {
  final paid = order['status'] == 'paid';
  final receipt = order['receipt'] as Map<String, dynamic>? ?? const {};
  final header = (receipt['header'] as String?)?.trim() ?? '';
  final footer = (receipt['footer'] as String?)?.trim() ?? '';
  final items = (order['items'] as List).cast<Map<String, dynamic>>();

  final out = <PrintLine>[
    ..._bold(wrap((receipt['name'] as String?) ?? '').map(center)),
    if (header.isNotEmpty)
      for (final l in header.split('\n')) ..._plain(wrap(l).map(center)),
    PrintLine(divider()),
    PrintLine('Date: ${_time((order['paid_at'] ?? order['created_at']) as String)}'),
    if (order['cashier'] != null) ..._plain(wrap('Cashier: ${order['cashier']}')),
    if ((order['customer_label'] as String?)?.isNotEmpty ?? false) ..._plain(wrap('Customer: ${order['customer_label']}')),
    // Kode member saja (bukan no HP): struk bisa terbawa / dibuang pelanggan.
    if (order['customer'] case {'code': final String code, 'anonymized': false}) PrintLine('Member: $code'),
    ..._plain(wrap('Transaction No: ${order['number']}')),
    PrintLine(divider()),
  ];

  final reward = order['reward'] as Map<String, dynamic>?;
  for (final item in items) {
    final qty = item['qty'] as int;
    final unit = (item['unit_price'] as int) + (item['modifiers_total'] as int);
    // Tambahan berjumlah: "Extra shot x2" (huruf x biasa: aman di semua printer thermal).
    final options = (item['modifiers'] as List)
        .cast<Map<String, dynamic>>()
        .map((m) => (m['qty'] as int? ?? 1) > 1 ? '${m['name']} x${m['qty']}' : '${m['name']}')
        .join(', ');
    out.addAll(_bold(wrap(options.isEmpty ? item['name'] as String : '${item['name']} $options')));
    if (item['note'] != null) out.addAll(_plain(wrap('  * ${item['note']}')));
    out.addAll(_plain(leftRight('  $qty x ${rupiah(unit)}', rupiah(qty * unit))));
    final disc = item['discount_total'] as int;
    // Porsi gratis dari hadiah loyalitas ditulis "Hadiah", bukan diskon.
    if (disc > 0) out.addAll(_plain(leftRight(reward?['item_id'] == item['id'] ? '  Hadiah' : '  Diskon', '-${rupiah(disc)}')));
  }

  final itemDiscounts = items.fold<int>(0, (s, i) => s + (i['discount_total'] as int));
  final orderDiscount = (order['discount_total'] as int) - itemDiscounts;
  final payments = paid ? (order['payments'] as List).cast<Map<String, dynamic>>() : const <Map<String, dynamic>>[];

  out
    ..add(PrintLine(divider()))
    ..add(PrintLine('Total Qty: ${items.fold<int>(0, (s, i) => s + (i['qty'] as int))}'))
    ..addAll(_plain(leftRight('  Sub Total', rupiah(order['subtotal'] as int))));
  if (orderDiscount > 0) {
    final label = reward != null && reward['item_id'] == null ? '  Hadiah ${reward['name']}' : '  Diskon';
    out.addAll(_plain(leftRight(label, '-${rupiah(orderDiscount)}')));
  }
  // Persen tarif saat transaksi, supaya pelanggan tahu besarnya (order lama tanpa tarif: label saja).
  if ((order['service_total'] as int) > 0) {
    final label = withRate('Service', order['service_bp'] as int?, included: order['service_inclusive'] == true);
    out.addAll(_plain(leftRight('  $label', rupiah(order['service_total'] as int))));
  }
  if ((order['tax_total'] as int) > 0) {
    final label = withRate('Pajak', order['tax_bp'] as int?, included: order['tax_inclusive'] == true);
    out.addAll(_plain(leftRight('  $label', rupiah(order['tax_total'] as int))));
  }
  if ((order['rounding'] as int) != 0) out.addAll(_plain(leftRight('  Pembulatan', rupiah(order['rounding'] as int))));
  out.addAll(_bold(leftRight('  Total', rupiah(order['grand_total'] as int))));

  for (final p in payments) {
    final label = _methodLabel[p['method']] ?? '${p['method']}';
    out.addAll(_plain(leftRight('  Bayar ($label)', rupiah((p['tendered'] ?? p['amount']) as int))));
  }
  if (payments.any((p) => p['method'] == 'cash')) {
    out.addAll(_plain(leftRight('  Kembalian', rupiah(order['change_total'] as int))));
  }

  out.add(PrintLine(divider()));
  // Stempel / poin member (order lunas): didapat, ditukar, saldo sekarang.
  if (order['loyalty'] case {'program': final String program, 'unit': final String unit, 'earned': final int earned,
      'redeemed': final int redeemed, 'balance': final int balance}) {
    out.add(PrintLine(program, bold: true));
    if (earned > 0) out.addAll(_plain(leftRight('  Dapat', '+$earned $unit')));
    if (redeemed > 0) out.addAll(_plain(leftRight('  Ditukar', '-$redeemed $unit')));
    out
      ..addAll(_plain(leftRight('  Saldo', '$balance $unit')))
      ..add(PrintLine(divider()));
  }
  if (!paid) out.add(PrintLine(center('*** BELUM DIBAYAR ***'), bold: true));
  if (footer.isNotEmpty) {
    for (final l in footer.split('\n')) {
      out.addAll(_plain(wrap(l).map(center)));
    }
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
