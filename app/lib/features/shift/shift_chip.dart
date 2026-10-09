import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';

import 'cash_dialogs.dart';
import 'shift_controller.dart';
import 'shift_dialogs.dart';

/// Menu shift terbuka: kas keluar, kas masuk, catatan kas, tutup shift.
Future<void> _menu(BuildContext context, WidgetRef ref) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true, // layar pendek (HP landscape): isi bisa digulir
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (value, icon, label, sub) in const [
          ('out', Icons.north_east_rounded, 'Kas keluar', 'Beli bahan, gas, upah harian, setor ke owner'),
          ('in', Icons.south_west_rounded, 'Kas masuk', 'Tambah uang kecil untuk kembalian'),
          ('list', Icons.list_alt_rounded, 'Catatan kas shift ini', 'Lihat atau batalkan yang salah catat'),
          ('close', Icons.lock_rounded, 'Tutup shift', 'Hitung uang di laci'),
        ])
          ListTile(
            leading: Icon(icon),
            title: Text(label, style: AppType.bodyStrong),
            subtitle: Text(sub),
            onTap: () => Navigator.pop(context, value),
          ),
        const SizedBox(height: AppSpace.s2),
        ]),
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case 'out' || 'in':
      if (await showCashDialog(context, kind: action) && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action == 'out' ? 'Kas keluar dicatat.' : 'Kas masuk dicatat.')));
      }
    case 'list':
      await showCashListDialog(context);
    default:
      await showCloseShiftDialog(context, ref);
  }
}

/// Status shift di app bar: ketuk untuk membuka shift, atau (bila terbuka) kas keluar/masuk & tutup shift.
/// [compact] = label pendek untuk HP.
class ShiftChip extends ConsumerWidget {
  const ShiftChip({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(shiftProvider);

    return shift.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => ActionChip(
        avatar: const Icon(Icons.sync_problem_rounded, size: 18, color: AppColors.danger),
        label: const Text('Shift ?'),
        onPressed: () => ref.invalidate(shiftProvider),
      ),
      data: (s) {
        if (s == null) {
          return ActionChip(
            avatar: const Icon(Icons.lock_open_rounded, size: 18, color: AppColors.warning),
            color: const WidgetStatePropertyAll(AppColors.warningSoft),
            side: const BorderSide(color: AppColors.warningSoft),
            label: Text(compact ? 'Buka shift' : 'Shift belum dibuka · Buka'),
            onPressed: () => showOpenShiftDialog(context, ref),
          );
        }
        final opened = DateTime.parse(s['opened_at'] as String).toLocal();
        final time = '${opened.hour.toString().padLeft(2, '0')}:${opened.minute.toString().padLeft(2, '0')}';
        return ActionChip(
          avatar: const Icon(Icons.circle, size: 10, color: AppColors.success),
          color: const WidgetStatePropertyAll(AppColors.successSoft),
          side: const BorderSide(color: AppColors.successSoft),
          tooltip: 'Shift: kas keluar/masuk, tutup shift',
          label: Text(compact ? 'Shift $time' : 'Shift sejak $time · Kas & tutup'),
          onPressed: () => _menu(context, ref),
        );
      },
    );
  }
}
