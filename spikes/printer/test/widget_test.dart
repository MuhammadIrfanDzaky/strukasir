import 'package:flutter_test/flutter_test.dart';
import 'package:printer_spike/receipt_format.dart';

void main() {
  test('format rupiah', () {
    expect(rupiah(0), '0');
    expect(rupiah(13000), '13.000');
    expect(rupiah(1250000), '1.250.000');
    expect(rupiah(-5000), '-5.000');
  });

  test('semua baris struk maksimal 32 karakter', () {
    final lines = customerReceipt(
      shopName: 'BerryBrew',
      orderNo: 'T1-0042',
      dateTime: '03/10/2026 14:48',
      cashier: 'Kasir',
      items: const [
        SpikeItem('Kopi Susu Gula Aren Spesial BerryBrew Large Sekali', 12, 1250000,
            modifiers: ['Extra shot (+5.000)'], note: 'es dipisah ya kak, gula sedikit saja'),
      ],
      paid: true,
      tendered: 20000000,
    );
    for (final l in lines) {
      expect(l.length, lessThanOrEqualTo(kLineWidth), reason: '"$l"');
    }
  });

  test('angka rata kanan', () {
    final l = leftRight('TOTAL', 'Rp 28.000');
    expect(l, hasLength(1));
    expect(l.first, hasLength(kLineWidth));
    expect(l.first.endsWith('Rp 28.000'), isTrue);
  });
}
