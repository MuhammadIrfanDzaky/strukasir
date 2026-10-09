import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../cart/dialogs.dart';
import '../cart/order_api.dart';
import '../menu/menu_controller.dart';
import '../printing/printer_service.dart';
import '../printing/receipt_format.dart';
import '../printing/receipt_preview.dart';
import '../session/session_controller.dart';
import '../shift/shift_controller.dart';
import '../customers/messaging.dart';
import '../printing/stations.dart';

String _isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
    final res = await ref
        .read(sessionProvider.notifier)
        .authed((api, token) => api.get('/orders?date=${_isoDate(_date)}&per_page=50$q', token: token));
    return (res['data'] as List).cast<OrderJson>();
  }

  void _reload() => setState(() => _orders = _load());

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final gutter = compact ? AppSpace.s3 : AppSpace.s5;
    final dateButton = OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today_rounded, size: 20),
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
    );
    final search = TextField(
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded),
        hintText: 'Cari nomor order / nama',
        isDense: true,
      ),
      onSubmitted: (v) {
        _query = v.trim();
        _reload();
      },
    );
    final refresh = IconButton(tooltip: 'Muat ulang', onPressed: _reload, icon: const Icon(Icons.refresh_rounded));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.s4, gutter, AppSpace.s3),
          // HP: tanggal + muat ulang di baris atas, kolom cari selebar layar di bawahnya.
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [dateButton, const Spacer(), refresh]),
                    const SizedBox(height: AppSpace.s2),
                    search,
                  ],
                )
              : Row(
                  children: [
                    dateButton,
                    const SizedBox(width: AppSpace.s3),
                    Expanded(child: search),
                    const SizedBox(width: AppSpace.s2),
                    refresh,
                  ],
                ),
        ),
        Expanded(
          child: FutureBuilder<List<OrderJson>>(
            future: _orders,
            builder: (context, snap) {
              if (snap.hasError) {
                final e = snap.error;
                return AppErrorState(message: e is ApiException ? e.message : '$e', onRetry: _reload);
              }
              if (!snap.hasData) return const AppLoading();
              final orders = snap.data!;
              if (orders.isEmpty) {
                return AppEmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'Belum ada transaksi',
                  message: _query.isEmpty
                      ? 'Tidak ada order pada ${_isoDate(_date)}.'
                      : 'Tidak ada yang cocok dengan "$_query".',
                );
              }
              return Padding(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) => _OrderTile(order: orders[i], onChanged: _reload),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onChanged});

  final OrderJson order;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String;
    final created = DateTime.parse(order['created_at'] as String).toLocal();
    final time = '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';

    final compact = context.isCompact;
    final total = Text(
      rp(order['grand_total'] as int),
      textAlign: TextAlign.right,
      style: AppType.bodyStrong.copyWith(
        color: status == 'void' ? AppColors.inkMuted : AppColors.ink,
        decoration: status == 'void' ? TextDecoration.lineThrough : null,
      ),
    );
    final items = Text(
      (order['items'] as List).cast<Map<String, dynamic>>().map((i) => '${i['qty']}x ${i['name']}').join(', '),
      maxLines: compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );

    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: compact ? AppSpace.s3 : AppSpace.s4),
      horizontalTitleGap: compact ? AppSpace.s2 : AppSpace.s4,
      // HP: jam masuk ke baris judul (kolom jam terpisah terlalu sempit di HP kecil).
      leading: compact
          ? null
          : SizedBox(
              width: 48,
              child: Text(time, style: AppType.bodyStrong.copyWith(color: AppColors.inkMuted)),
            ),
      title: Text(
        [if (compact) time, order['number'] as String, (order['customer_label'] as String?) ?? '']
            .where((p) => p.isNotEmpty)
            .join(compact ? ' · ' : '  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // HP: status pindah ke bawah judul supaya nama & item tidak terhimpit.
      subtitle: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                items,
                const SizedBox(height: AppSpace.s1),
                AppBadge.orderStatus(status),
              ],
            )
          : items,
      trailing: compact
          ? total
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBadge.orderStatus(status),
                const SizedBox(width: AppSpace.s4),
                SizedBox(width: 100, child: total),
              ],
            ),
      onTap: () async {
        final changed = await showDialog<bool>(
          context: context,
          builder: (_) => OrderDetailDialog(order: order),
        );
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

  /// Cetak ulang tiket bar/dapur seluruh item order (mis. tiket hilang / printer bar sempat mati).
  Future<void> _reprintTickets() async {
    final o = widget.order;
    final menu = ref.read(menuProvider).value?.menu;
    final stations = ref.read(stationsProvider).value ?? const <TicketStation>[];
    final items = orderTicketItems(o, (id) => menu?.product(id)?.categoryId ?? '');
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      for (final s in stations) {
        final mine = items.where((i) => s.takes(i.categoryId)).toList();
        if (mine.isEmpty) continue;
        await ref.read(printerProvider.notifier).printTo(
              s.printerMac,
              kitchenTicket(
                station: s.name,
                number: o['number'] as String,
                label: o['customer_label'] as String?,
                items: mine,
                at: DateTime.now(),
                reprint: true,
              ),
              copies: s.copies,
            );
      }
      messenger.showSnackBar(const SnackBar(content: Text('Tiket dicetak ulang.')));
    } on PrintException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reprint() async {
    try {
      await ref.read(printerProvider.notifier).printDocument(
            customerReceipt(widget.order),
            logoBase64: ref.read(menuProvider).value?.menu.receipt.logoBase64,
          );
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
        scrollable: true,
        title: Text('Void ${widget.order['number']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.order['status'] == 'paid')
              Text(
                'Uang ${rp(widget.order['grand_total'] as int)} dikembalikan ke pelanggan dan dicatat di shift ini.',
              ),
            const SizedBox(height: AppSpace.s3),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Alasan (wajib)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    Approval? approval;
    if (!(user?.can('order.void') ?? false)) {
      approval = await showDialog<Approval>(
        context: context,
        builder: (_) => const ApprovalDialog(reason: 'Void order butuh persetujuan owner.'),
      );
      if (approval == null) return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .authed(
            (api, token) => api.post(
              '/orders/${widget.order['id']}/void',
              token: token,
              data: {
                'reason': reason.text.trim(),
                if (approval != null) 'approval': {'user_id': approval.userId, 'pin': approval.pin},
              },
            ),
          );
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
      scrollable: true,
      title: Row(
        children: [
          Expanded(child: Text('Order ${o['number']}')),
          AppBadge.orderStatus(o['status'] as String),
        ],
      ),
      // Pratinjau persis seperti struk yang akan dicetak.
      content: SizedBox(
        width: 400,
        child: ReceiptPreview(lines: lines, logoBase64: ref.watch(menuProvider).value?.menu.receipt.logoBase64),
      ),
      actions: [
        if (o['status'] != 'void')
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _busy ? null : _void,
            child: const Text('Void'),
          ),
        if (o['status'] == 'paid') TextButton(onPressed: _busy ? null : _reprint, child: const Text('Cetak ulang')),
        if (o['status'] != 'void' && (ref.watch(stationsProvider).value?.isNotEmpty ?? false))
          TextButton(onPressed: _busy ? null : _reprintTickets, child: const Text('Cetak tiket')),
        // Struk digital ke member (fitur pesan WhatsApp); server menolak bila member tanpa no HP.
        if (o['status'] == 'paid' &&
            o['customer'] is Map &&
            (o['customer'] as Map)['anonymized'] != true &&
            (ref.watch(menuProvider).value?.menu.feature('customer_messaging') ?? false))
          TextButton(
            onPressed: _busy
                ? null
                : () => openWhatsApp(context, ref, (o['customer'] as Map)['id'] as String, 'receipt', orderId: o['id'] as String),
            child: const Text('Struk via WA'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
      ],
    );
  }
}
