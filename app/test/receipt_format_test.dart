import 'package:berrybrew_pos/core/money.dart';
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
    for (final doc in [customerReceipt(order()), customerReceipt(order(status: 'open'))]) {
      for (final line in doc) {
        expect(line.text.length, lessThanOrEqualTo(kLineWidth), reason: '"${line.text}"');
      }
    }
  });

  test('struk lunas mengikuti format BerryBrew', () {
    final lines = customerReceipt(order());
    final text = lines.join('\n');
    expect(lines.first.text.trim(), 'BerryBrew');
    expect(lines.first.bold, isTrue, reason: 'nama kedai tebal');
    expect(text, contains('Jl. Contoh No. 1'));
    expect(text, contains('Date: '));
    expect(text, contains('Cashier: Kasir 1'));
    expect(text, contains('Customer: Mas Andi / Meja 3'));
    expect(text, contains('Transaction No: T1-0042'));
    // Nama item + pilihan dalam satu baris tebal, lalu qty × harga.
    final item = lines.firstWhere((l) => l.text.startsWith('Americano'));
    expect(item.text, 'Americano Cold');
    expect(item.bold, isTrue);
    expect(text, contains('  1 x 15.000'));
    expect(text, contains('* es dipisah'));
    expect(text, contains('Total Qty: 3'));
    expect(text, contains('Sub Total'));
    expect(text, contains('-5.000')); // diskon order = 9.600 - 4.600
    expect(lines.firstWhere((l) => l.text.startsWith('  Total ')).bold, isTrue);
    expect(text, contains('Bayar (cash)'));
    expect(text, contains('60.000'));
    expect(text, contains('Kembalian'));
    expect(text, contains('8.600'));
    expect(text, contains('Terima kasih!'));
    expect(text, isNot(contains('CHECKER')));
  });

  test('bill belum bayar tanpa baris pembayaran', () {
    final text = customerReceipt(order(status: 'open')).join('\n');
    expect(text, contains('BELUM DIBAYAR'));
    expect(text, isNot(contains('Kembalian')));
    expect(text, isNot(contains('Bayar (')));
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

  test('pajak & service menampilkan persen saat transaksi (order lama: tanpa persen)', () {
    final withRates = {...order(), 'service_total': 2570, 'tax_total': 5397, 'service_bp': 500, 'tax_bp': 1000};
    final text = customerReceipt(withRates).map((l) => l.text).join(' | ');
    expect(text, contains('Service 5%'));
    expect(text, contains('Pajak 10%'));

    final old = {...order(), 'service_total': 2570, 'tax_total': 5397};
    final oldText = customerReceipt(old).map((l) => l.text).join(' | ');
    expect(oldText, contains('  Pajak'));
    expect(oldText, isNot(contains('%')));
  });

  test('persen dari basis poin', () {
    expect(percentBp(1000), '10%');
    expect(percentBp(550), '5,5%');
    expect(percentBp(1125), '11,25%');
    expect(withRate('Pajak', null), 'Pajak');
    expect(withRate('Pajak', 0), 'Pajak');
  });

  test('tambahan berjumlah tercetak dengan jumlahnya', () {
    final o = order();
    final items = (o['items'] as List).cast<Map<String, dynamic>>();
    items[0] = {
      ...items[0],
      'modifiers': [
        {'group_name': 'Tambahan', 'name': 'Extra shot', 'price_delta': 5000, 'qty': 2},
      ],
    };
    final text = customerReceipt({...o, 'items': items}).map((l) => l.text).join(' | ');
    expect(text, contains('Extra shot x2'));
  });

  test('harga termasuk pajak: struk menulis "Termasuk pajak 10%"', () {
    final o = {...order(), 'tax_total': 4673, 'tax_bp': 1000, 'tax_inclusive': true};
    final text = customerReceipt(o).map((l) => l.text).join(' | ');
    expect(text, contains('Termasuk pajak 10%'));
  });
}
