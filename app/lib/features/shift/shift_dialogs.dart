import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../printing/printer_service.dart';
import '../printing/receipt_format.dart';
import 'shift_controller.dart';

/// Minta modal awal lalu buka shift. Mengembalikan true jika shift terbuka.
Future<bool> showOpenShiftDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  String? error;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        scrollable: true,
        title: const Text('Buka shift'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Hitung uang tunai di laci sebelum mulai berjualan.',
                style: AppType.body.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpace.s4),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Modal awal', prefixText: 'Rp ', errorText: error),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final cash = parseRupiah(controller.text);
              if (cash == null) return setState(() => error = 'Isi nominal (boleh 0)');
              try {
                await ref.read(shiftProvider.notifier).open(cash);
                if (context.mounted) Navigator.pop(context, true);
              } on ApiException catch (e) {
                setState(() => error = e.message);
              }
            },
            child: const Text('Buka shift'),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Tutup shift dengan hitung kas "buta": kasir memasukkan uang yang ada di laci tanpa melihat
/// angka sistem; selisih baru ditampilkan setelah ditutup.
Future<void> showCloseShiftDialog(BuildContext context, WidgetRef ref) async {
  final counted = TextEditingController();
  final note = TextEditingController();
  String? error;

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        scrollable: true,
        title: const Text('Tutup shift'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Hitung semua uang tunai di laci (termasuk modal awal).',
                style: AppType.body.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpace.s4),
            TextField(
              controller: counted,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Uang tunai di laci', prefixText: 'Rp ', errorText: error),
            ),
            const SizedBox(height: AppSpace.s3),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final cash = parseRupiah(counted.text);
              if (cash == null) return setState(() => error = 'Isi nominal');
              try {
                final closed = await ref.read(shiftProvider.notifier).close(cash, note.text.trim());
                if (context.mounted) Navigator.pop(context, closed);
              } on ApiException catch (e) {
                setState(() => error = e.message);
              }
            },
            child: const Text('Tutup shift'),
          ),
        ],
      ),
    ),
  );

  if (result == null || !context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => ShiftResultDialog(shift: result));
}

class ShiftResultDialog extends ConsumerWidget {
  const ShiftResultDialog({super.key, required this.shift});

  final Map<String, dynamic> shift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = shift['summary'] as Map<String, dynamic>;
    final byMethod = summary['by_method'] as Map<String, dynamic>;
    final diff = shift['difference'] as int;
    return AlertDialog(
      scrollable: true,
      title: const Text('Shift ditutup'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppSummaryRow('Modal awal', rp(summary['opening_cash'] as int)),
          AppSummaryRow('Tunai masuk', rp(summary['cash_in'] as int)),
          if ((summary['cash_refund'] as int) > 0)
            AppSummaryRow('Refund tunai', '-${rp(summary['cash_refund'] as int)}'),
          AppSummaryRow('Kas seharusnya', rp(shift['expected_cash'] as int)),
          AppSummaryRow('Kas dihitung', rp(shift['counted_cash'] as int)),
          Container(
            margin: const EdgeInsets.symmetric(vertical: AppSpace.s3),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: AppSpace.s2),
            decoration: BoxDecoration(
              color: diff == 0 ? AppColors.successSoft : AppColors.dangerSoft,
              borderRadius: AppRadius.mdAll,
            ),
            child: AppSummaryRow(
              diff == 0 ? 'Selisih' : (diff > 0 ? 'Lebih' : 'Kurang'),
              rp(diff.abs()),
              emphasis: true,
              valueColor: diff == 0 ? AppColors.success : AppColors.danger,
            ),
          ),
          AppSummaryRow('Order lunas', '${summary['paid_orders']}'),
          AppSummaryRow('Debit', rp(byMethod['debit'] as int)),
          AppSummaryRow('QRIS', rp(byMethod['qris'] as int)),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            try {
              await ref.read(printerProvider.notifier).printLines(shiftReport(shift));
            } on PrintException catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              }
            }
          },
          child: const Text('Cetak laporan shift'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Selesai')),
      ],
    );
  }
}
