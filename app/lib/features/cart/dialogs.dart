import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../session/login_screen.dart';
import '../session/session_controller.dart';
import 'order_api.dart';
import 'pricing.dart';

/// Input diskon: nominal (Rp) atau persen. Null = hapus diskon.
Future<(bool, Discount?)> showDiscountDialog(BuildContext context, {Discount? current, required int maxAmount}) async {
  var percent = current?.type == DiscountType.percent;
  final controller = TextEditingController(
    text: current == null ? '' : (percent ? '${current.value / 100}'.replaceAll(RegExp(r'\.0$'), '') : rupiah(current.value)),
  );
  String? error;

  final result = await showDialog<(bool, Discount?)>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        scrollable: true,
        title: const Text('Diskon'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Rupiah')),
              ButtonSegment(value: true, label: Text('Persen')),
            ],
            selected: {percent},
            onSelectionChanged: (s) => setState(() => percent = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: percent ? null : 'Rp ',
              suffixText: percent ? '%' : null,
              errorText: error,
            ),
          ),
        ]),
        actions: [
          if (current != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(context, (true, null)),
              child: const Text('Hapus diskon'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              if (percent) {
                final p = double.tryParse(controller.text.replaceAll(',', '.'));
                if (p == null || p <= 0 || p > 100) return setState(() => error = 'Isi 0–100');
                Navigator.pop(context, (true, Discount.percent((p * 100).round())));
              } else {
                final v = parseRupiah(controller.text);
                if (v == null || v <= 0 || v > maxAmount) return setState(() => error = 'Maksimal ${rupiah(maxAmount)}');
                Navigator.pop(context, (true, Discount.amount(v)));
              }
            },
            child: const Text('Terapkan'),
          ),
        ],
      ),
    ),
  );
  return result ?? (false, null);
}

/// Owner memasukkan PIN di tablet kasir untuk menyetujui aksi (diskon di atas batas, dll.).
class ApprovalDialog extends ConsumerStatefulWidget {
  const ApprovalDialog({super.key, required this.reason});

  final String reason;

  @override
  ConsumerState<ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends ConsumerState<ApprovalDialog> {
  String? _ownerId;
  final _pin = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffProvider);
    final owners = staff.value?.where((s) => s.role == 'owner').toList() ?? const <StaffMember>[];
    _ownerId ??= owners.firstOrNull?.id;

    return AlertDialog(
      scrollable: true,
      title: const Text('Persetujuan owner'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.reason, style: AppType.body.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s4),
          if (staff.isLoading) const LinearProgressIndicator(),
          if (owners.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _ownerId,
              decoration: const InputDecoration(labelText: 'Owner'),
              items: [for (final o in owners) DropdownMenuItem(value: o.id, child: Text(o.name))],
              onChanged: (v) => setState(() => _ownerId = v),
            ),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'PIN owner'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: _ownerId == null
              ? null
              : () {
                  if (!RegExp(r'^\d{4,6}$').hasMatch(_pin.text)) return;
                  Navigator.pop(context, Approval(_ownerId!, _pin.text));
                },
          child: const Text('Setujui'),
        ),
      ],
    );
  }
}

/// Daftar open bill ("struk belum dibayar") — pilih untuk dilanjutkan.
class OpenBillsDialog extends ConsumerWidget {
  const OpenBillsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Open Bill (belum dibayar)'),
      content: SizedBox(
        width: 520,
        height: (MediaQuery.sizeOf(context).height * 0.6).clamp(240.0, 420.0),
        child: FutureBuilder<List<OrderJson>>(
          future: ref.read(orderApiProvider).openOrders(),
          builder: (context, snap) {
            if (snap.hasError) {
              final e = snap.error;
              return AppEmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Gagal memuat',
                message: e is ApiException ? e.message : '$e',
              );
            }
            if (!snap.hasData) return const AppLoading();
            final orders = snap.data!;
            if (orders.isEmpty) {
              return const AppEmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'Tidak ada Open Bill',
                message: 'Semua order sudah dibayar. Ketuk "Open Bill" di keranjang untuk menyimpan order yang belum dibayar.',
              );
            }
            return ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (_, i) {
                final o = orders[i];
                return ListTile(
                  title: Text('${o['number']}  ·  ${(o['customer_label'] as String?) ?? '-'}'),
                  subtitle: Text((o['items'] as List)
                      .cast<Map<String, dynamic>>()
                      .map((it) => '${it['qty']}x ${it['name']}')
                      .join(', ')),
                  trailing: Text(rp(o['grand_total'] as int)),
                  onTap: () => Navigator.pop(context, o),
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
    );
  }
}
