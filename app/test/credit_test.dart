import 'package:berrybrew_pos/core/theme/theme.dart';
import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/cart/order_api.dart';
import 'package:berrybrew_pos/features/cart/payment_dialog.dart';
import 'package:berrybrew_pos/features/customers/customer_api.dart';
import 'package:berrybrew_pos/features/printing/receipt_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'receipt_format_test.dart' show order;

void main() {
  test('data kasbon pelanggan dibaca dari API', () {
    final c = Customer.fromJson({
      'id': 'c1', 'code': 'M0001', 'name': 'Pak Budi', 'credit_balance': 40000, 'credit_limit': 500000, 'credit_limit_custom': false,
    });
    expect([c.creditBalance, c.creditLimit, c.creditLimitCustom], [40000, 500000, false]);
    expect(Customer.fromJson({'id': 'c', 'code': 'M', 'name': 'X'}).creditBalance, isNull, reason: 'fitur mati');
  });

  test('pembayaran kasbon tanpa uang diterima', () {
    expect(PaymentDraft(method: 'credit', amount: 20000).toJson(), containsPair('method', 'credit'));
    expect(PaymentDraft(method: 'credit', amount: 20000).toJson().containsKey('tendered'), isFalse);
  });

  test('struk: metode kasbon & sisa kasbon', () {
    final paid = order();
    final text = customerReceipt({
      ...paid,
      'payments': [
        {'method': 'cash', 'amount': 20000, 'tendered': 20000, 'change': 0},
        {'method': 'credit', 'amount': 31400, 'tendered': null, 'change': 0},
      ],
      'change_total': 0,
      'credit': {'amount': 31400, 'balance': 71400},
    }).join('\n');
    expect(text, contains('Bayar (kasbon)'));
    expect(text, contains('Sisa kasbon'));
    expect(text, contains('71.400'));
  });

  test('bukti pelunasan & laporan shift menyebut kasbon', () {
    final text = creditRepaymentReceipt(
      {'amount': 15000, 'method': 'cash', 'tendered': 20000, 'change': 5000, 'balance': 25000, 'created_at': '2026-10-09T03:00:00Z'},
      customerName: 'Pak Budi',
      cashier: 'Kasir 1',
      shopName: 'Warung Bu Tini',
    ).join('\n');
    for (final s in ['BUKTI PELUNASAN KASBON', 'Pak Budi', '15.000', 'Kembalian', '25.000']) {
      expect(text, contains(s));
    }

    final report = shiftReport({
      'opened_at': '2026-10-09T00:00:00Z', 'closed_at': '2026-10-09T10:00:00Z', 'opened_by': 'A', 'closed_by': 'A',
      'expected_cash': 115000, 'counted_cash': 115000, 'difference': 0, 'note': null,
      'summary': {
        'opening_cash': 100000, 'cash_in': 0, 'cash_refund': 0, 'credit_repaid_cash': 15000,
        'by_method': {'cash': 0, 'debit': 0, 'qris': 0, 'credit': 40000}, 'paid_orders': 1, 'refunds': 0,
      },
    }).join('\n');
    expect(report, contains('Kasbon (belum dibayar)'));
    expect(report, contains('Pelunasan tunai'));
  });

  testWidgets('pilihan Kasbon hanya untuk member, dengan peringatan lewat batas', (t) async {
    Future<void> pump(CartCustomer? c) => t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: PaymentDialog(total: 40000, splitEnabled: false, number: 'T1-0001', creditCustomer: c)),
        ));

    await pump(null);
    expect(find.text('Kasbon'), findsNothing);

    await pump(const CartCustomer(id: 'c1', code: 'M0001', name: 'Pak Budi', creditBalance: 480000, creditLimit: 500000));
    await t.tap(find.text('Kasbon'));
    await t.pump();
    expect(find.text('Melewati batas: perlu PIN owner.'), findsOneWidget);
    expect(find.text('Catat kasbon'), findsOneWidget);
  });
}
