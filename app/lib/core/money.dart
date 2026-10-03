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

/// Parse input kasir ("13.000", "13000", "Rp 13.000") ke integer. Null jika tidak valid.
int? parseRupiah(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}
