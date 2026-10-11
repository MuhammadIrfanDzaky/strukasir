import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import 'cart_controller.dart';
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
  const PaymentDialog({super.key, required this.total, required this.splitEnabled, required this.number, this.creditCustomer});

  final int total;
  final bool splitEnabled;
  final String number;

  /// Member yang boleh kasbon (fitur aktif & member tertaut); null = pilihan Kasbon disembunyikan.
  final CartCustomer? creditCustomer;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  late final List<_Row> _rows = [_Row('cash', widget.total)];

  int get _sum => _rows.fold(0, (s, r) => s + r.amountValue);

  String? get _problem {
    if (_sum != widget.total) return 'Jumlah pembayaran ${rp(_sum)} ≠ total ${rp(widget.total)}';
    if (_rows.where((r) => r.method == 'cash').length > 1) return 'Tunai cukup satu baris';
    if (_rows.where((r) => r.method == 'credit').length > 1) return 'Kasbon cukup satu baris';
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
      scrollable: true,
      title: Text('Bayar ${widget.number}'),
      content: SizedBox(
        width: 520,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
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
              // Mengisi lebar dialog; di HP sempit ikon disembunyikan agar label tetap terbaca.
              Expanded(
                child: SegmentedButton<String>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  style: MediaQuery.sizeOf(context).width < 480
                      ? const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpace.s2)))
                      : null,
                  segments: [
                    for (final (value, label, icon) in [
                      ('cash', 'Tunai', Icons.payments_rounded),
                      ('debit', 'Debit', Icons.credit_card_rounded),
                      ('qris', 'QRIS', Icons.qr_code_rounded),
                      if (widget.creditCustomer != null) ('credit', 'Kasbon', Icons.menu_book_rounded),
                    ])
                      ButtonSegment(
                        value: value,
                        // Satu baris; mengecil sedikit bila 4 pilihan tidak muat di HP sempit.
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
                        icon: MediaQuery.sizeOf(context).width < 480 ? null : Icon(icon),
                      ),
                  ],
                  selected: {r.method},
                  onSelectionChanged: (s) => setState(() => r.method = s.first),
                ),
              ),
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
            if (r.method == 'credit') _creditNote(r.amountValue),
          ],
          if (widget.splitEnabled && _rows.length < 3)
            TextButton(onPressed: () => setState(() {
                final rest = widget.total - _sum;
                _rows.add(_Row('qris', rest > 0 ? rest : 0));
              }), child: const Text('Bagi ke metode lain'), ),
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
          child: Text(_rows.length == 1 && _rows.first.method == 'credit'
              ? 'Catat kasbon'
              : _rows.length == 1 && _rows.first.method != 'cash' ? 'Konfirmasi diterima' : 'Selesaikan'),
        ),
      ],
    );
  }
}

extension on _PaymentDialogState {
  /// Sisa kasbon sebelum & sesudah, dan peringatan bila melewati batas (owner diminta PIN).
  Widget _creditNote(int amount) {
    final c = widget.creditCustomer!;
    final before = c.creditBalance ?? 0;
    final after = before + amount;
    final over = c.creditLimit != null && after > c.creditLimit!;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s3),
      decoration: BoxDecoration(color: over ? AppColors.warningSoft : AppColors.surfaceSunken, borderRadius: AppRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Kasbon ${c.name}', style: AppType.bodyStrong),
        AppSummaryRow('Sisa sekarang', rp(before)),
        AppSummaryRow('Setelah transaksi ini', rp(after)),
        AppSummaryRow('Batas', c.creditLimit == null ? 'Tanpa batas' : rp(c.creditLimit!)),
        if (over)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s1),
            child: Text('Melewati batas: perlu PIN owner.', style: AppType.caption.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700)),
          ),
      ]),
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
