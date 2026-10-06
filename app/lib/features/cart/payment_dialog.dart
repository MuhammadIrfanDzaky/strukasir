import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import 'order_api.dart';

/// Nominal tunai yang umum diserahkan pelanggan, mis. total 28.000 → 28.000 / 30.000 / 50.000 / 100.000.
List<int> suggestedCash(int total) {
  final options = <int>{total};
  for (final step in [5000, 10000, 20000, 50000, 100000]) {
    options.add(((total + step - 1) ~/ step) * step);
  }
  return (options.where((v) => v >= total).toList()..sort()).take(5).toList();
}

class _Row {
  _Row(this.method, int amount)
      : amount = TextEditingController(text: rupiah(amount)),
        tendered = TextEditingController();

  String method;
  final TextEditingController amount;
  final TextEditingController tendered;

  int get amountValue => parseRupiah(amount.text) ?? 0;
  int? get tenderedValue => parseRupiah(tendered.text);
}

/// Pilih metode bayar. Mengembalikan daftar pembayaran yang jumlahnya tepat = total.
class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key, required this.total, required this.splitEnabled, required this.number});

  final int total;
  final bool splitEnabled;
  final String number;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  late final List<_Row> _rows = [_Row('cash', widget.total)];

  int get _sum => _rows.fold(0, (s, r) => s + r.amountValue);

  String? get _problem {
    if (_sum != widget.total) return 'Jumlah pembayaran ${rp(_sum)} ≠ total ${rp(widget.total)}';
    if (_rows.where((r) => r.method == 'cash').length > 1) return 'Tunai cukup satu baris';
    for (final r in _rows) {
      if (r.amountValue <= 0) return 'Nominal harus lebih dari 0';
      if (r.method == 'cash' && (r.tenderedValue ?? r.amountValue) < r.amountValue) return 'Uang diterima kurang';
    }
    return null;
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.amount.dispose();
      r.tendered.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;

    return AlertDialog(
      title: Text('Bayar ${widget.number}'),
      content: SizedBox(
        width: 520,
        child: ListView(shrinkWrap: true, children: [
          Container(
            padding: const EdgeInsets.all(AppSpace.s4),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.lgAll),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const AppOverline('Total tagihan', color: AppColors.primaryStrong),
              Text(rp(widget.total), style: AppType.display.copyWith(color: AppColors.primaryStrong)),
            ]),
          ),
          const SizedBox(height: AppSpace.s2),
          for (final (i, r) in _rows.indexed) ...[
            if (i > 0) const Padding(padding: EdgeInsets.only(top: AppSpace.s3), child: Divider()),
            const SizedBox(height: AppSpace.s3),
            Row(children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('Tunai'), icon: Icon(Icons.payments_rounded)),
                  ButtonSegment(value: 'debit', label: Text('Debit'), icon: Icon(Icons.credit_card_rounded)),
                  ButtonSegment(value: 'qris', label: Text('QRIS'), icon: Icon(Icons.qr_code_rounded)),
                ],
                selected: {r.method},
                onSelectionChanged: (s) => setState(() => r.method = s.first),
              ),
              const Spacer(),
              if (_rows.length > 1)
                IconButton(
                    tooltip: 'Hapus baris',
                    onPressed: () => setState(() => _rows.removeAt(i)),
                    icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: AppSpace.s3),
            if (_rows.length > 1) ...[
              TextField(
                controller: r.amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp '),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpace.s3),
            ],
            if (r.method == 'cash') ...[
              TextField(
                controller: r.tendered,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Uang diterima', prefixText: 'Rp '),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpace.s2),
              Wrap(spacing: AppSpace.s2, runSpacing: AppSpace.s2, children: [
                for (final v in suggestedCash(r.amountValue))
                  ActionChip(
                    label: Text(v == r.amountValue ? 'Uang pas' : rupiah(v)),
                    onPressed: () => setState(() => r.tendered.text = rupiah(v)),
                  ),
              ]),
              if ((r.tenderedValue ?? 0) > r.amountValue)
                Container(
                  margin: const EdgeInsets.only(top: AppSpace.s3),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: AppSpace.s3),
                  decoration: BoxDecoration(color: AppColors.successSoft, borderRadius: AppRadius.mdAll),
                  child: AppSummaryRow('Kembalian', rp(r.tenderedValue! - r.amountValue),
                      emphasis: true, valueColor: AppColors.success),
                ),
            ],
            if (r.method == 'qris')
              const _Note('Pastikan notifikasi dana masuk muncul di aplikasi merchant QRIS sebelum konfirmasi. '
                  'Nama Anda tercatat sebagai pengonfirmasi.'),
            if (r.method == 'debit') const _Note('Konfirmasi setelah transaksi di mesin EDC berhasil.'),
          ],
          if (widget.splitEnabled && _rows.length < 3)
            TextButton.icon(
              onPressed: () => setState(() {
                final rest = widget.total - _sum;
                _rows.add(_Row('qris', rest > 0 ? rest : 0));
              }),
              icon: const Icon(Icons.call_split_rounded),
              label: const Text('Bagi ke metode lain'),
            ),
          if (problem != null && _rows.length > 1)
            Text(problem, style: AppType.caption.copyWith(color: AppColors.danger)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: problem != null
              ? null
              : () => Navigator.pop(context, [
                    for (final r in _rows)
                      PaymentDraft(
                        method: r.method,
                        amount: r.amountValue,
                        tendered: r.method == 'cash' ? (r.tenderedValue ?? r.amountValue) : null,
                      ),
                  ]),
          child: Text(_rows.length == 1 && _rows.first.method != 'cash' ? 'Konfirmasi diterima' : 'Selesaikan'),
        ),
      ],
    );
  }
}

/// Catatan prosedur untuk metode non-tunai.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpace.s3),
        decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: AppRadius.mdAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.inkMuted),
          const SizedBox(width: AppSpace.s2),
          Expanded(child: Text(text, style: AppType.body)),
        ]),
      );
}
