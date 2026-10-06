import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../menu/menu_controller.dart';
import '../session/session_controller.dart';
import 'cart_controller.dart';
import 'checkout_flow.dart';
import 'dialogs.dart';
import 'order_api.dart';

class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key});

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  bool _busy = false;
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(CheckoutFlow flow) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(CheckoutFlow(ref, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBills() async {
    final menu = ref.read(menuProvider).value?.menu;
    final order = await showDialog<OrderJson>(context: context, builder: (_) => const OpenBillsDialog());
    if (order == null || menu == null) return;
    if (!ref.read(cartProvider).isEmpty && mounted) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          content: const Text('Keranjang saat ini akan diganti. Lanjutkan?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ganti')),
          ],
        ),
      );
      if (replace != true) return;
    }
    ref.read(cartProvider.notifier).loadOrder(order, menu);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final totals = ref.watch(cartTotalsProvider);
    final menu = ref.watch(menuProvider).value?.menu;
    final user = (ref.watch(sessionProvider).value as LoggedIn?)?.user;
    final notifier = ref.read(cartProvider.notifier);
    final canDiscount = (menu?.feature('discounts') ?? false) &&
        ((user?.can('discount.within_limit') ?? false) || (user?.can('discount.over_limit') ?? false));
    final openBill = menu?.feature('open_bill') ?? false;
    final canAct = !_busy && !cart.isEmpty;

    if (_label.text != cart.customerLabel) _label.text = cart.customerLabel;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s5, AppSpace.s3, AppSpace.s2, 0),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const AppOverline('Pesanan'),
                  Text(cart.isSaved ? 'Order ${cart.number}' : 'Order baru', style: AppType.titleLg),
                ]),
              ),
              if (openBill)
                TextButton.icon(
                  onPressed: _busy ? null : _openBills,
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Belum dibayar'),
                ),
              IconButton(
                tooltip: 'Kosongkan',
                onPressed: canAct ? notifier.clear : null,
                icon: const Icon(Icons.delete_sweep_rounded),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s5, AppSpace.s3, AppSpace.s5, AppSpace.s2),
            child: TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Nama pelanggan / meja',
                isDense: true,
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              onChanged: notifier.setCustomerLabel,
            ),
          ),
          Expanded(
            child: cart.isEmpty
                ? const AppEmptyState(
                    icon: Icons.touch_app_rounded,
                    title: 'Keranjang kosong',
                    message: 'Ketuk produk di kiri untuk menambahkan.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(indent: AppSpace.s5, endIndent: AppSpace.s5),
                    itemBuilder: (_, i) {
                      final l = cart.lines[i];
                      final discount = totals.lineDiscounts.length > i ? totals.lineDiscounts[i] : 0;
                      final meta = [
                        ...l.modifiers.map((m) => m.name),
                        if (l.note != null && l.note!.isNotEmpty) '“${l.note}”',
                      ].join(' · ');
                      return InkWell(
                        onTap: () => _editLine(l, canDiscount),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpace.s5, AppSpace.s2, AppSpace.s4, AppSpace.s2),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(l.product.name, style: AppType.bodyStrong),
                                if (meta.isNotEmpty)
                                  Text(meta, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                                if (discount > 0)
                                  Text('Diskon -${rupiah(discount)}',
                                      style: AppType.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                            _QtyStepper(
                              qty: l.qty,
                              onMinus: () => notifier.setQty(l.id, l.qty - 1),
                              onPlus: () => notifier.setQty(l.id, l.qty + 1),
                            ),
                            SizedBox(
                              width: 84,
                              child: Text(rupiah(l.unitPrice * l.qty - discount),
                                  textAlign: TextAlign.right, style: AppType.bodyStrong),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpace.s5, AppSpace.s3, AppSpace.s5, AppSpace.s4),
            decoration: const BoxDecoration(
              color: AppColors.surfaceApp,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSummaryRow('Subtotal', rupiah(totals.subtotal)),
              if (totals.orderDiscount > 0)
                AppSummaryRow('Diskon', '-${rupiah(totals.orderDiscount)}', valueColor: AppColors.success),
              if (totals.serviceTotal > 0) AppSummaryRow('Service', rupiah(totals.serviceTotal)),
              if (totals.taxTotal > 0) AppSummaryRow('Pajak', rupiah(totals.taxTotal)),
              if (totals.rounding != 0) AppSummaryRow('Pembulatan', rupiah(totals.rounding)),
              const SizedBox(height: AppSpace.s1),
              AppSummaryRow('Total', rp(totals.grandTotal), emphasis: true),
              if (canDiscount && !cart.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                    onPressed: () async {
                      final (changed, d) = await showDiscountDialog(context,
                          current: cart.orderDiscount, maxAmount: totals.subtotal);
                      if (changed) notifier.setOrderDiscount(d);
                    },
                    icon: const Icon(Icons.percent_rounded, size: 18),
                    label: Text(cart.orderDiscount == null ? 'Diskon order' : 'Ubah diskon order'),
                  ),
                ),
              const SizedBox(height: AppSpace.s3),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canAct ? () => _run((f) => f.printChecker()) : null,
                    child: const Text('Checker'),
                  ),
                ),
                if (openBill) ...[
                  const SizedBox(width: AppSpace.s2),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: canAct ? () => _run((f) => f.holdBill()) : null,
                      child: const Text('Simpan, belum bayar', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: AppSpace.s2),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg), textStyle: AppType.title),
                onPressed: canAct ? () => _run((f) => f.pay()) : null,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text('Bayar ${rp(totals.grandTotal)}'),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _editLine(CartLine line, bool canDiscount) async {
    final notifier = ref.read(cartProvider.notifier);
    final note = TextEditingController(text: line.note);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(line.product.name),
        content: TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'Catatan (mis. es dipisah)'),
          maxLength: 120,
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () {
              notifier.setQty(line.id, 0);
              Navigator.pop(context);
            },
            child: const Text('Hapus item'),
          ),
          if (canDiscount)
            TextButton(
              onPressed: () async {
                final (changed, d) =
                    await showDiscountDialog(context, current: line.discount, maxAmount: line.unitPrice * line.qty);
                if (changed) notifier.setLineDiscount(line.id, d);
              },
              child: const Text('Diskon item'),
            ),
          FilledButton(
            onPressed: () {
              notifier.setNote(line.id, note.text);
              Navigator.pop(context);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}

/// Tombol −/+ jumlah item. Ukuran 40 agar muat di panel, area sentuh tetap 48 lewat padding baris.
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.qty, required this.onMinus, required this.onPlus});

  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, VoidCallback onPressed, String tooltip) => IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(40),
            backgroundColor: AppColors.surfaceSunken,
            foregroundColor: AppColors.ink,
            shape: const CircleBorder(),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(Icons.remove_rounded, onMinus, 'Kurangi'),
      SizedBox(width: 32, child: Text('$qty', textAlign: TextAlign.center, style: AppType.title)),
      button(Icons.add_rounded, onPlus, 'Tambah'),
    ]);
  }
}
