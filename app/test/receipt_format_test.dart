import 'package:berrybrew_pos/features/cart/payment_dialog.dart';
import 'package:berrybrew_pos/features/printing/receipt_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bentuk sama dengan OrderResource dari server.
Map<String, dynamic> order({String status = 'paid'}) => {
      'id': 'o1',
      'number': 'T1-0042',
      'status': status,
      'customer_label': 'Mas Andi / Meja 3',
      'cashier': 'Kasir 1',
      'created_at': '2026-10-03T07:48:00Z',
      'paid_at': status == 'paid' ? '2026-10-03T07:50:00Z' : null,
      'items': [
        {
          'id': 'i1', 'name': 'Americano', 'unit_price': 13000, 'modifiers_total': 2000, 'qty': 1,
          'note': null, 'discount_total': 0, 'line_total': 15000,
          'modifiers': [{'group_name': 'Suhu', 'name': 'Cold', 'price_delta': 2000}],
        },
        {
          'id': 'i2', 'name': 'Kopi Susu Gula Aren Spesial BerryBrew Ukuran Besar', 'unit_price': 18000,
          'modifiers_total': 5000, 'qty': 2, 'note': 'es dipisah ya kak, gula sedikit', 'discount_total': 4600,
          'line_total': 41400,
          'modifiers': [{'group_name': 'Tambahan', 'name': 'Extra shot', 'price_delta': 5000}],
        },
      ],
      'subtotal': 56400,
      'discount_total': 9600,
      'service_total': 0,
      'tax_total': 0,
      'rounding': 0,
      'grand_total': 51400,
      'change_total': 8600,
      'payments': [
        {'method': 'cash', 'amount': 51400, 'tendered': 60000, 'change': 8600},
      ],
      'receipt': {'name': 'BerryBrew', 'header': 'Jl. Contoh No. 1', 'footer': 'Terima kasih!'},
    };

void main() {
  test('semua baris struk muat di kertas 58mm (32 karakter)', () {
    for (final doc in [customerReceipt(order()), customerReceipt(order(status: 'open')), checker(order())]) {
      for (final line in doc) {
        expect(line.length, lessThanOrEqualTo(kLineWidth), reason: '"$line"');
      }
    }
  });

  test('struk lunas memuat total, pembayaran, kembalian, dan footer', () {
    final text = customerReceipt(order()).join('\n');
    expect(text, contains('T1-0042'));
    expect(text, contains('+ Cold'));
    expect(text, contains('-5.000')); // diskon order = 9.600 - 4.600
    expect(text, contains('Rp 51.400'));
    expect(text, contains('60.000'));
    expect(text, contains('8.600'));
    expect(text, contains('LUNAS'));
    expect(text, contains('Terima kasih!'));
  });

  test('bill belum bayar tanpa baris pembayaran', () {
    final text = customerReceipt(order(status: 'open')).join('\n');
    expect(text, contains('BELUM DIBAYAR'));
    expect(text, isNot(contains('Kembali')));
  });

  test('checker tanpa harga, dengan catatan', () {
    final text = checker(order()).join('\n');
    expect(text, contains('2x Kopi Susu'));
    expect(text, contains('* es dipisah'));
    expect(text, isNot(contains('13.000')));
  });

  test('laporan shift muat 58mm dan menandai kekurangan kas', () {
    final shift = {
      'opened_at': '2026-10-03T00:00:00Z',
      'opened_by': 'Kasir 1',
      'closed_at': '2026-10-03T10:00:00Z',
      'closed_by': 'Kasir 1',
      'expected_cash': 120000,
      'counted_cash': 118000,
      'difference': -2000,
      'note': 'uang receh kurang',
      'summary': {
        'opening_cash': 100000, 'cash_in': 20000, 'cash_refund': 0, 'expected_cash': 120000,
        'by_method': {'cash': 20000, 'debit': 0, 'qris': 20000}, 'paid_orders': 2, 'refunds': 0,
      },
    };
    final lines = shiftReport(shift);
    for (final l in lines) {
      expect(l.length, lessThanOrEqualTo(kLineWidth), reason: '"$l"');
    }
    expect(lines.join('\n'), contains('KURANG'));
    expect(lines.join('\n'), contains('2.000'));
  });

  test('saran nominal tunai', () {
    expect(suggestedCash(28000), [28000, 30000, 40000, 50000, 100000]);
    expect(suggestedCash(50000), [50000, 60000, 100000]); // 60.000 = 3 lembar 20 ribu
  });
}
