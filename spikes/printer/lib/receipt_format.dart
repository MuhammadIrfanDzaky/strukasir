// Formatter struk 58mm (32 karakter per baris, Font A).
// Fungsi murni tanpa ketergantungan printer, supaya layout bisa diuji di unit test.

const int kLineWidth = 32;

String rupiah(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buf';
}

/// Memecah teks menjadi baris selebar [width], memotong di spasi bila bisa.
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

/// Teks kiri dan kanan dalam satu baris; jika tidak muat, teks kiri di-wrap
/// dan nilai kanan ditaruh di baris terakhir.
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

class SpikeItem {
  final String name;
  final int qty;
  final int price;
  final List<String> modifiers;
  final String? note;
  const SpikeItem(this.name, this.qty, this.price,
      {this.modifiers = const [], this.note});
}

/// Struk pelanggan (lunas atau belum bayar).
List<String> customerReceipt({
  required String shopName,
  required String orderNo,
  required String dateTime,
  required String cashier,
  required List<SpikeItem> items,
  required bool paid,
  int? tendered,
}) {
  final total = items.fold<int>(0, (s, i) => s + i.qty * i.price);
  final out = <String>[
    center(shopName),
    divider(),
    'No   : $orderNo',
    'Waktu: $dateTime',
    'Kasir: $cashier',
    divider(),
  ];
  for (final i in items) {
    out.addAll(wrap(i.name));
    for (final m in i.modifiers) {
      out.addAll(wrap('  + $m'));
    }
    if (i.note != null) out.addAll(wrap('  * ${i.note}'));
    out.addAll(leftRight('  ${i.qty} x ${rupiah(i.price)}', rupiah(i.qty * i.price)));
  }
  out
    ..add(divider())
    ..addAll(leftRight('TOTAL', 'Rp ${rupiah(total)}'));
  if (paid && tendered != null) {
    out
      ..addAll(leftRight('Tunai', rupiah(tendered)))
      ..addAll(leftRight('Kembali', rupiah(tendered - total)));
  }
  out
    ..add(divider())
    ..add(center(paid ? 'LUNAS - Terima kasih!' : '*** BELUM DIBAYAR ***'));
  return out;
}

/// Checker untuk barista: tanpa harga, fokus ke item, modifier, catatan.
List<String> checker({
  required String orderNo,
  required String customer,
  required List<SpikeItem> items,
}) {
  final out = <String>[
    center('CHECKER'),
    'No  : $orderNo',
    'Nama: $customer',
    divider(),
  ];
  for (final i in items) {
    out.addAll(wrap('${i.qty}x ${i.name}'));
    for (final m in i.modifiers) {
      out.addAll(wrap('   + $m'));
    }
    if (i.note != null) out.addAll(wrap('   * ${i.note}'));
  }
  out.add(divider());
  return out;
}
