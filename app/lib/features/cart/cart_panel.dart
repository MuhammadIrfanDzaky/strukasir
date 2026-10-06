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

/// Letak panel keranjang: samping katalog (tablet landscape), bawah katalog (tablet portrait),
/// atau halaman penuh (HP).
enum CartDock { side, bottom, page }

class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key, this.dock = CartDock.side, this.onClose, this.hostRef, this.hostContext});

  final CartDock dock;

  /// Tombol tutup di header (halaman keranjang HP).
  final VoidCallback? onClose;

  /// Ref & context layar pemilik. Dipakai alur bayar agar dialog setelahnya (Lunas, kembalian)
  /// tetap tampil walau panel ini sudah ditutup: halaman keranjang HP menutup diri saat kosong.
  final WidgetRef? hostRef;
  final BuildContext? hostContext;

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  bool _busy = false;
  final _label = TextEditingController();
  final _labelFocus = FocusNode();

  /// Kolom nama dipindah antar-susunan (tinggi ↔ pendek) saat keyboard muncul. GlobalKey menjaga
  /// state & fokusnya tetap sama, sehingga keyboard tidak langsung tertutup lagi.
  final _labelKey = GlobalKey(debugLabel: 'customer-label');
  String? _labelError;

  @override
  void dispose() {
    _label.dispose();
    _labelFocus.dispose();
    super.dispose();
  }

  /// Nama pelanggan / meja wajib sebelum Cek pesanan, Open Bill, atau Bayar.
  bool _requireLabel() {
    if (ref.read(cartProvider).customerLabel.trim().isNotEmpty) return true;
    setState(() => _labelError = 'Isi nama pelanggan / meja dulu');
    _labelFocus.requestFocus();
    return false;
  }

  Future<void> _act(Future<void> Function(CheckoutFlow flow) action) async {
    if (_requireLabel()) await _run(action);
  }

  /// Rincian pesanan untuk dicek ulang bersama pelanggan sebelum Open Bill / Bayar.
  /// Hanya tampilan: tidak menyimpan dan tidak mencetak apa pun.
  Future<void> _reviewOrder() => showDialog<void>(
    context: context,
    builder: (context) {
      final cart = ref.read(cartProvider);
      final totals = ref.read(cartTotalsProvider);
      final count = cart.lines.fold<int>(0, (n, l) => n + l.qty);
      return AlertDialog(
        scrollable: true,
        title: Text(cart.isSaved ? 'Cek pesanan · ${cart.number}' : 'Cek pesanan'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 20, color: AppColors.inkMuted),
                  const SizedBox(width: AppSpace.s2),
                  Expanded(child: Text(cart.customerLabel.trim(), style: AppType.title)),
                  AppBadge('$count item'),
                ],
              ),
              const SizedBox(height: AppSpace.s3),
              const Divider(height: 1),
              for (final (i, l) in cart.lines.indexed) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 36, child: Text('${l.qty}×', style: AppType.bodyStrong)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.product.name, style: AppType.bodyStrong),
                            if (l.modifiers.isNotEmpty)
                              Text(
                                l.modifiers.map((m) => m.name).join(', '),
                                style: AppType.caption.copyWith(color: AppColors.inkMuted),
                              ),
                            if (l.note != null && l.note!.isNotEmpty)
                              Text('Catatan: ${l.note}', style: AppType.caption.copyWith(color: AppColors.warning)),
                            if (totals.lineDiscounts.length > i && totals.lineDiscounts[i] > 0)
                              Text(
                                'Diskon -${rupiah(totals.lineDiscounts[i])}',
                                style: AppType.caption.copyWith(color: AppColors.success),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        rupiah(l.unitPrice * l.qty - (totals.lineDiscounts.length > i ? totals.lineDiscounts[i] : 0)),
                        style: AppType.bodyStrong,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
              const SizedBox(height: AppSpace.s3),
              AppSummaryRow('Subtotal', rupiah(totals.subtotal)),
              if (totals.orderDiscount > 0)
                AppSummaryRow('Diskon', '-${rupiah(totals.orderDiscount)}', valueColor: AppColors.success),
              if (totals.serviceTotal > 0) AppSummaryRow('Service', rupiah(totals.serviceTotal)),
              if (totals.taxTotal > 0) AppSummaryRow('Pajak', rupiah(totals.taxTotal)),
              if (totals.rounding != 0) AppSummaryRow('Pembulatan', rupiah(totals.rounding)),
              AppSummaryRow('Total', rp(totals.grandTotal), emphasis: true),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      );
    },
  );

  Future<void> _run(Future<void> Function(CheckoutFlow flow) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(CheckoutFlow(widget.hostRef ?? ref, widget.hostContext ?? context));
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
          scrollable: true,
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
    final canDiscount =
        (menu?.feature('discounts') ?? false) &&
        ((user?.can('discount.within_limit') ?? false) || (user?.can('discount.over_limit') ?? false));
    final openBill = menu?.feature('open_bill') ?? false;
    final canAct = !_busy && !cart.isEmpty;

    if (_label.text != cart.customerLabel) _label.text = cart.customerLabel;

    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 380;
        final gutter = narrow ? AppSpace.s4 : AppSpace.s5;

        final header = Padding(
          padding: EdgeInsets.fromLTRB(widget.onClose == null ? gutter : AppSpace.s1, AppSpace.s3, AppSpace.s2, 0),
          child: Row(
            children: [
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'Kembali ke menu',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppOverline('Pesanan'),
                    Text(cart.isSaved ? 'Order ${cart.number}' : 'Order baru', style: AppType.titleLg),
                  ],
                ),
              ),
              if (openBill)
                narrow
                    ? IconButton(
                        tooltip: 'Open Bill',
                        onPressed: _busy ? null : _openBills,
                        icon: const Icon(Icons.receipt_long_rounded),
                      )
                    : TextButton.icon(
                        onPressed: _busy ? null : _openBills,
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text('Open Bill'),
                      ),
              IconButton(
                tooltip: 'Kosongkan',
                onPressed: canAct ? notifier.clear : null,
                icon: const Icon(Icons.delete_sweep_rounded),
              ),
            ],
          ),
        );

        final labelField = Padding(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.s3, gutter, AppSpace.s2),
          child: TextField(
            key: _labelKey,
            controller: _label,
            focusNode: _labelFocus,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Nama pelanggan / meja *',
              isDense: true,
              prefixIcon: const Icon(Icons.person_outline_rounded),
              errorText: _labelError,
            ),
            onChanged: (v) {
              notifier.setCustomerLabel(v);
              if (_labelError != null && v.trim().isNotEmpty) setState(() => _labelError = null);
            },
          ),
        );

        Widget line(int i) {
          final l = cart.lines[i];
          final discount = totals.lineDiscounts.length > i ? totals.lineDiscounts[i] : 0;
          final meta = [
            ...l.modifiers.map((m) => m.name),
            if (l.note != null && l.note!.isNotEmpty) '“${l.note}”',
          ].join(' · ');
          return InkWell(
            onTap: () => _editLine(l, canDiscount),
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpace.s2, AppSpace.s3, AppSpace.s2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.product.name, style: AppType.bodyStrong),
                        if (meta.isNotEmpty) Text(meta, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                        if (discount > 0)
                          Text(
                            'Diskon -${rupiah(discount)}',
                            style: AppType.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                  _QtyStepper(
                    dense: box.maxWidth < 420,
                    qty: l.qty,
                    onMinus: () => notifier.setQty(l.id, l.qty - 1),
                    onPlus: () => notifier.setQty(l.id, l.qty + 1),
                  ),
                  SizedBox(
                    width: narrow ? 72 : 84,
                    child: Text(
                      rupiah(l.unitPrice * l.qty - discount),
                      textAlign: TextAlign.right,
                      style: AppType.bodyStrong,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        const empty = AppEmptyState(
          icon: Icons.touch_app_rounded,
          title: 'Keranjang kosong',
          message: 'Ketuk produk untuk menambahkan.',
        );
        const divider = Divider(indent: AppSpace.s5, endIndent: AppSpace.s5);

        final breakdown = <Widget>[
          AppSummaryRow('Subtotal', rupiah(totals.subtotal)),
          if (totals.orderDiscount > 0)
            AppSummaryRow('Diskon', '-${rupiah(totals.orderDiscount)}', valueColor: AppColors.success),
          if (totals.serviceTotal > 0) AppSummaryRow('Service', rupiah(totals.serviceTotal)),
          if (totals.taxTotal > 0) AppSummaryRow('Pajak', rupiah(totals.taxTotal)),
          if (totals.rounding != 0) AppSummaryRow('Pembulatan', rupiah(totals.rounding)),
          if (canDiscount && !cart.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                onPressed: () async {
                  final (changed, d) = await showDiscountDialog(
                    context,
                    current: cart.orderDiscount,
                    maxAmount: totals.subtotal,
                  );
                  if (changed) notifier.setOrderDiscount(d);
                },
                icon: const Icon(Icons.percent_rounded, size: 18),
                label: Text(cart.orderDiscount == null ? 'Diskon order' : 'Ubah diskon order'),
              ),
            ),
        ];

        final actions = <Widget>[
          AppSummaryRow('Total', rp(totals.grandTotal), emphasis: true),
          const SizedBox(height: AppSpace.s2),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  // Padding kecil supaya label tidak patah di panel sempit.
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpace.s3)),
                  // Tampilkan rincian pesanan untuk dicek bersama pelanggan; tidak menyimpan, tidak mencetak.
                  onPressed: canAct
                      ? () {
                          if (_requireLabel()) _reviewOrder();
                        }
                      : null,
                  child: const Text('Cek pesanan', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (openBill) ...[
                const SizedBox(width: AppSpace.s2),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpace.s3)),
                    onPressed: canAct ? () => _act((f) => f.openBill()) : null,
                    // Order dari daftar Open Bill: simpan tambahan pesanan, tetap belum dibayar.
                    child: Text(cart.isSaved ? 'Simpan Bill' : 'Open Bill', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpace.s2),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(AppSize.touchLg),
              textStyle: AppType.title,
            ),
            onPressed: canAct ? () => _act((f) => f.pay()) : null,
            child: _busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text('Bayar ${rp(totals.grandTotal)}'),
          ),
        ];

        // Tinggi cukup: daftar item scroll sendiri, rincian + tombol selalu terlihat di bawah.
        // Pendek (HP landscape, dok bawah): semua ikut scroll; hanya total + tombol yang menempel.
        final short = box.maxHeight < 560;
        final body = short
            ? ListView(
                padding: EdgeInsets.zero,
                children: [
                  header,
                  labelField,
                  if (cart.isEmpty)
                    const SizedBox(height: 220, child: empty)
                  else
                    for (var i = 0; i < cart.lines.length; i++) ...[if (i > 0) divider, line(i)],
                  Padding(
                    padding: EdgeInsets.fromLTRB(gutter, AppSpace.s2, gutter, AppSpace.s2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: breakdown),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  labelField,
                  Expanded(
                    child: cart.isEmpty
                        ? empty
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
                            itemCount: cart.lines.length,
                            separatorBuilder: (_, _) => divider,
                            itemBuilder: (_, i) => line(i),
                          ),
                  ),
                ],
              );

        final footer = Container(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.s3, gutter, AppSpace.s3),
          decoration: const BoxDecoration(
            color: AppColors.surfaceApp,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: short ? actions : [...breakdown, const SizedBox(height: AppSpace.s1), ...actions],
            ),
          ),
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: switch (widget.dock) {
              CartDock.side => const Border(left: BorderSide(color: AppColors.line)),
              CartDock.bottom => const Border(top: BorderSide(color: AppColors.line)),
              CartDock.page => null,
            },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: body),
              footer,
            ],
          ),
        );
      },
    );
  }

  Future<void> _editLine(CartLine line, bool canDiscount) async {
    final notifier = ref.read(cartProvider.notifier);
    final note = TextEditingController(text: line.note);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
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
                final (changed, d) = await showDiscountDialog(
                  context,
                  current: line.discount,
                  maxAmount: line.unitPrice * line.qty,
                );
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
  const _QtyStepper({required this.qty, required this.onMinus, required this.onPlus, this.dense = false});

  final int qty;

  /// Panel sempit: tombol 36 dp (area sentuh tetap ±48 dp lewat padding baris).
  final bool dense;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, VoidCallback onPressed, String tooltip) => IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: dense ? 18 : 20),
      style: IconButton.styleFrom(
        minimumSize: Size.square(dense ? 36 : 40),
        fixedSize: dense ? const Size.square(36) : null,
        padding: EdgeInsets.zero,
        backgroundColor: AppColors.surfaceSunken,
        foregroundColor: AppColors.ink,
        shape: const CircleBorder(),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.remove_rounded, onMinus, 'Kurangi'),
        SizedBox(
          width: dense ? 28 : 32,
          child: Text('$qty', textAlign: TextAlign.center, style: AppType.title),
        ),
        button(Icons.add_rounded, onPlus, 'Tambah'),
      ],
    );
  }
}

/// Keranjang layar penuh untuk HP. Menutup diri saat keranjang kosong (bayar, simpan, kosongkan).
class CartPage extends ConsumerWidget {
  const CartPage({super.key, required this.hostRef, required this.hostContext});

  final WidgetRef hostRef;
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(cartProvider, (prev, next) {
      if (next.isEmpty && (prev?.isEmpty == false) && Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: CartPanel(
          dock: CartDock.page,
          onClose: () => Navigator.of(context).pop(),
          hostRef: hostRef,
          hostContext: hostContext,
        ),
      ),
    );
  }
}
