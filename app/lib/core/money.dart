/// Format rupiah tanpa desimal: 13000 → "13.000". Nominal selalu integer.
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

/// "Rp 13.000"
String rp(int amount) => 'Rp ${rupiah(amount)}';

/// Basis poin → persen: 1000 → "10%", 550 → "5,5%", 1125 → "11,25%".
String percentBp(int bp) {
  final whole = bp ~/ 100;
  final frac = (bp % 100).toString().padLeft(2, '0').replaceFirst(RegExp(r'0+$'), '');
  return frac.isEmpty ? '$whole%' : '$whole,$frac%';
}

/// "Pajak 10%" — label dengan persen bila tarif diketahui (order lama: tanpa persen).
/// [included] = harga sudah termasuk → "Termasuk Pajak 10%" (tidak menambah total).
String withRate(String label, int? bp, {bool included = false}) {
  final text = bp == null || bp <= 0 ? label : '$label ${percentBp(bp)}';
  return included ? 'Termasuk ${text[0].toLowerCase()}${text.substring(1)}' : text;
}

/// Parse input kasir ("13.000", "13000", "Rp 13.000") ke integer. Null jika tidak valid.
int? parseRupiah(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}
