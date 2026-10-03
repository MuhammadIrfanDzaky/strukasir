import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../cart/dialogs.dart';
import '../cart/order_api.dart';
import '../printing/printer_service.dart';
import '../printing/receipt_format.dart';
import '../session/session_controller.dart';
import '../shift/shift_controller.dart';

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Riwayat transaksi per hari bisnis: cari, lihat detail, cetak ulang, void.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  DateTime _date = DateTime.now();
  String _query = '';
  late Future<List<OrderJson>> _orders = _load();

  Future<List<OrderJson>> _load() async {
    final q = _query.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(_query)}';
    final res = await ref.read(sessionProvider.notifier).authed(
        (api, token) => api.get('/orders?date=${_isoDate(_date)}&per_page=50$q', token: token));
    return (res['data'] as List).cast<OrderJson>();
  }

  void _reload() => setState(() => _orders = _load());

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(_isoDate(_date)),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 366)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                _date = picked;
                _reload();
              }
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Cari nomor order / nama', isDense: true),
              onSubmitted: (v) {
                _query = v.trim();
                _reload();
              },
            ),
          ),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<OrderJson>>(
          future: _orders,
          builder: (context, snap) {
            if (snap.hasError) {
              final e = snap.error;
              return Center(child: Text(e is ApiException ? e.message : '$e'));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final orders = snap.data!;
            if (orders.isEmpty) return const Center(child: Text('Belum ada transaksi.'));
            return ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _OrderTile(order: orders[i], onChanged: _reload),
            );
          },
        ),
      ),
    ]);
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onChanged});

  final OrderJson order;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String;
    final scheme = Theme.of(context).colorScheme;
    final created = DateTime.parse(order['created_at'] as String).toLocal();
    final time = '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';

    return ListTile(
      leading: Text(time),
      title: Text('${order['number']}  ${(order['customer_label'] as String?) ?? ''}'),
      subtitle: Text((order['items'] as List)
          .cast<Map<String, dynamic>>()
          .map((i) => '${i['qty']}x ${i['name']}')
          .join(', ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Chip(
          label: Text(switch (status) { 'paid' => 'Lunas', 'open' => 'Belum bayar', _ => 'Void' }),
          backgroundColor: status == 'void' ? scheme.errorContainer : null,
        ),
        const SizedBox(width: 12),
        SizedBox(width: 90, child: Text(rp(order['grand_total'] as int), textAlign: TextAlign.right)),
      ]),
      onTap: () async {
        final changed = await showDialog<bool>(context: context, builder: (_) => OrderDetailDialog(order: order));
        if (changed == true) onChanged();
      },
    );
  }
}

class OrderDetailDialog extends ConsumerStatefulWidget {
  const OrderDetailDialog({super.key, required this.order});

  final OrderJson order;

  @override
  ConsumerState<OrderDetailDialog> createState() => _OrderDetailDialogState();
}

class _OrderDetailDialogState extends ConsumerState<OrderDetailDialog> {
  bool _busy = false;

  Future<void> _reprint() async {
    try {
      await ref.read(printerProvider.notifier).printLines(customerReceipt(widget.order));
    } on PrintException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _void() async {
    final user = (ref.read(sessionProvider).value as LoggedIn?)?.user;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Void ${widget.order['number']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.order['status'] == 'paid')
            Text('Uang ${rp(widget.order['grand_total'] as int)} dikembalikan ke pelanggan dan dicatat di shift ini.'),
          TextField(controller: reason, autofocus: true, decoration: const InputDecoration(labelText: 'Alasan (wajib)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Void')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    Approval? approval;
    if (!(user?.can('order.void') ?? false)) {
      approval = await showDialog<Approval>(
          context: context, builder: (_) => const ApprovalDialog(reason: 'Void order butuh persetujuan owner.'));
      if (approval == null) return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).authed((api, token) => api.post(
            '/orders/${widget.order['id']}/void',
            token: token,
            data: {
              'reason': reason.text.trim(),
              if (approval != null) 'approval': {'user_id': approval.userId, 'pin': approval.pin},
            },
          ));
      ref.invalidate(shiftProvider);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      _snack(e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final lines = customerReceipt(o);

    return AlertDialog(
      title: Text('Order ${o['number']}'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          // Pratinjau persis seperti struk yang akan dicetak.
          child: Text(lines.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ),
      ),
      actions: [
        if (o['status'] != 'void')
          TextButton(onPressed: _busy ? null : _void, child: const Text('Void')),
        if (o['status'] == 'paid')
          TextButton(onPressed: _busy ? null : _reprint, child: const Text('Cetak ulang')),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
      ],
    );
  }
}
