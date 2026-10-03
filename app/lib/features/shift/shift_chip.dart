import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shift_controller.dart';
import 'shift_dialogs.dart';

/// Status shift di app bar: ketuk untuk membuka / menutup shift.
class ShiftChip extends ConsumerWidget {
  const ShiftChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(shiftProvider);

    return shift.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => ActionChip(
        avatar: const Icon(Icons.sync_problem, size: 18),
        label: const Text('Shift ?'),
        onPressed: () => ref.invalidate(shiftProvider),
      ),
      data: (s) {
        if (s == null) {
          return ActionChip(
            avatar: const Icon(Icons.lock_open, size: 18),
            label: const Text('Buka shift'),
            onPressed: () => showOpenShiftDialog(context, ref),
          );
        }
        final opened = DateTime.parse(s['opened_at'] as String).toLocal();
        final time = '${opened.hour.toString().padLeft(2, '0')}:${opened.minute.toString().padLeft(2, '0')}';
        return ActionChip(
          avatar: const Icon(Icons.schedule, size: 18),
          label: Text('Shift sejak $time · Tutup'),
          onPressed: () => showCloseShiftDialog(context, ref),
        );
      },
    );
  }
}
