import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
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
    final theme = Theme.of(context);

    if (_label.text != cart.customerLabel) _label.text = cart.customerLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Text(cart.isSaved ? 'Order ${cart.number}' : 'Order baru', style: theme.textTheme.titleLarge),
            const Spacer(),
            if (openBill)
              TextButton.icon(
                onPressed: _busy ? null : _openBills,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Belum dibayar'),
              ),
            IconButton(
              tooltip: 'Kosongkan',
              onPressed: _busy || cart.isEmpty ? null : notifier.clear,
              icon: const Icon(Icons.delete_sweep),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Nama pelanggan / meja', isDense: true),
            onChanged: notifier.setCustomerLabel,
          ),
        ),
        Expanded(
          child: cart.isEmpty
              ? const Center(child: Text('Ketuk produk untuk menambahkan.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final l = cart.lines[i];
                    final discount = totals.lineDiscounts.length > i ? totals.lineDiscounts[i] : 0;
                    return ListTile(
                      dense: true,
                      title: Text(l.product.name),
                      subtitle: Text([
                        ...l.modifiers.map((m) => m.name),
                        if (l.note != null && l.note!.isNotEmpty) '“${l.note}”',
                        if (discount > 0) 'diskon -${rupiah(discount)}',
                      ].join(' · ')),
                      onTap: () => _editLine(l, canDiscount),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            onPressed: () => notifier.setQty(l.id, l.qty - 1),
                            icon: const Icon(Icons.remove_circle_outline)),
                        Text('${l.qty}', style: theme.textTheme.titleMedium),
                        IconButton(
                            onPressed: () => notifier.setQty(l.id, l.qty + 1),
                            icon: const Icon(Icons.add_circle_outline)),
                        SizedBox(
                          width: 76,
                          child: Text(rupiah(l.unitPrice * l.qty - discount), textAlign: TextAlign.right),
                        ),
                      ]),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(children: [
            _row('Subtotal', rupiah(totals.subtotal)),
            if (totals.orderDiscount > 0) _row('Diskon', '-${rupiah(totals.orderDiscount)}'),
            if (totals.serviceTotal > 0) _row('Service', rupiah(totals.serviceTotal)),
            if (totals.taxTotal > 0) _row('Pajak', rupiah(totals.taxTotal)),
            if (totals.rounding != 0) _row('Pembulatan', rupiah(totals.rounding)),
            _row('TOTAL', rp(totals.grandTotal), style: theme.textTheme.titleLarge),
            if (canDiscount && !cart.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final (changed, d) = await showDiscountDialog(context,
                        current: cart.orderDiscount, maxAmount: totals.subtotal);
                    if (changed) notifier.setOrderDiscount(d);
                  },
                  icon: const Icon(Icons.percent),
                  label: Text(cart.orderDiscount == null ? 'Diskon order' : 'Ubah diskon order'),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            OutlinedButton(
              onPressed: _busy || cart.isEmpty ? null : () => _run((f) => f.printChecker()),
              child: const Text('Checker'),
            ),
            const SizedBox(width: 8),
            if (openBill)
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy || cart.isEmpty ? null : () => _run((f) => f.holdBill()),
                  child: const Text('Simpan (belum bayar)'),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy || cart.isEmpty ? null : () => _run((f) => f.pay()),
                child: _busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Bayar ${rp(totals.grandTotal)}'),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {TextStyle? style}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [Text(label, style: style), const Spacer(), Text(value, style: style)]),
      );

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
