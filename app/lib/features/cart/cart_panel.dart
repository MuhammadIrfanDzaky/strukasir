import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../customers/credit_dialogs.dart';
import '../customers/customer_picker.dart';
import '../customers/member_tier.dart';
import '../loyalty/reward_dialog.dart';
import '../promotions/voucher_dialog.dart';
import '../menu/menu_controller.dart';
import '../menu/modifier_selection.dart';
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
  /// Fitur "Nama pelanggan / meja" dimatikan → kolom disembunyikan dan tidak wajib.
  bool _requireLabel() {
    if (!(ref.read(menuProvider).value?.menu.customerNameOn ?? true)) return true;
    if (ref.read(cartProvider).customerLabel.trim().isNotEmpty) return true;
    final hint = ref.read(menuProvider).value?.menu.customerLabelHint ?? 'Nama pelanggan / meja';
    setState(() => _labelError = 'Isi ${hint.toLowerCase()} dulu');
    _labelFocus.requestFocus();
    return false;
  }

  /// Cari / daftarkan member lalu tautkan ke order ini.
  Future<void> _pickMember() async {
    final menu = ref.read(menuProvider).value?.menu;
    final c = await pickCustomer(context, phoneRequired: menu?.customerPhoneRequired ?? true);
    if (c == null || !mounted) return;
    ref.read(cartProvider.notifier).setCustomer(
          CartCustomer(
              id: c.id, code: c.code, name: c.name, phone: c.phone, visits: c.visits, note: c.note, balance: c.loyaltyBalance, tier: c.tier,
              creditBalance: c.creditBalance, creditLimit: c.creditLimit),
        );
    if (_labelError != null) setState(() => _labelError = null);
  }

  /// Member membayar kasbonnya (di luar order ini): catat pelunasan, perbarui sisa di chip.
  Future<void> _repay() async {
    final c = ref.read(cartProvider).customer;
    if (c == null || (c.creditBalance ?? 0) <= 0) return;
    final left = await showRepayDialog(context, customerId: c.id, name: c.name, balance: c.creditBalance!);
    if (left == null || !mounted) return;
    ref.read(cartProvider.notifier).setCustomer(CartCustomer(
      id: c.id, code: c.code, name: c.name, phone: c.phone, visits: c.visits, note: c.note,
      balance: c.balance, tier: c.tier, creditBalance: left, creditLimit: c.creditLimit));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pelunasan kasbon dicatat. Sisa ${rp(left)}.')));
  }

  /// Tukar hadiah dengan saldo member.
  Future<void> _pickReward() async {
    final menu = ref.read(menuProvider).value?.menu;
    final cart = ref.read(cartProvider);
    final program = menu?.loyalty;
    if (menu == null || program == null || cart.customer == null) return;
    final picked = await pickReward(context, program: program, balance: cart.customer!.balance ?? 0, cart: cart, menu: menu);
    if (picked != null) ref.read(cartProvider.notifier).setReward(picked.$1, itemId: picked.$2);
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
      final pricing = ref.read(menuProvider).value?.menu.pricing;
      final pricingMenu = ref.read(menuProvider).value?.menu;
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
                  Expanded(
                    child: Text(cart.customerLabel.trim().isEmpty ? 'Pesanan' : cart.customerLabel.trim(),
                        style: AppType.title),
                  ),
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
                                modifierSummary(l.modifiers),
                                style: AppType.caption.copyWith(color: AppColors.inkMuted),
                              ),
                            if (l.note != null && l.note!.isNotEmpty)
                              Text('Catatan: ${l.note}', style: AppType.caption.copyWith(color: AppColors.warning)),
                            if (totals.lineDiscounts.length > i && totals.lineDiscounts[i] > 0)
                              Text(
                                '${l.id == cart.rewardItemId ? 'Hadiah' : (pricingMenu == null ? null : lineBenefit(cart, pricingMenu, l, DateTime.now()))?.label ?? 'Diskon'} -${rupiah(totals.lineDiscounts[i])}',
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
                AppSummaryRow(cart.reward != null && !cart.reward!.isFreeProduct
                    ? 'Hadiah: ${cart.reward!.name}'
                    : cart.voucher != null ? 'Voucher ${cart.voucher!.code}' : 'Diskon',
                    '-${rupiah(totals.orderDiscount)}', valueColor: AppColors.success),
              if (totals.serviceTotal > 0)
                AppSummaryRow(withRate('Service', pricing?.serviceBp, included: pricing?.serviceInclusive ?? false),
                    rupiah(totals.serviceTotal)),
              if (totals.taxTotal > 0)
                AppSummaryRow(withRate('Pajak', pricing?.taxBp, included: pricing?.taxInclusive ?? false),
                    rupiah(totals.taxTotal)),
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
    final askLabel = menu?.customerNameOn ?? true;
    final memberOn = (menu?.customersOn ?? false) && (user?.can('customers.view') ?? false);
    final program = memberOn ? menu?.loyalty : null;
    final earn = menu == null ? 0 : loyaltyEarnPreview(cart, menu, totals);
    final reward = cart.reward;
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
              labelText: '${menu?.customerLabelHint ?? 'Nama pelanggan / meja'} *',
              isDense: true,
              prefixIcon: const Icon(Icons.person_outline_rounded),
              errorText: _labelError,
              suffixIcon: memberOn && cart.customer == null
                  ? IconButton(
                      tooltip: 'Pilih member',
                      onPressed: _busy ? null : _pickMember,
                      icon: const Icon(Icons.person_search_rounded),
                    )
                  : null,
            ),
            onChanged: (v) {
              notifier.setCustomerLabel(v);
              if (_labelError != null && v.trim().isNotEmpty) setState(() => _labelError = null);
            },
          ),
        );

        // Member tertaut: nama · kode (+ catatan) dengan tombol lepas. Tanpa kolom nama (fitur dimatikan),
        // tombol "Tambah member" tampil sendiri.
        final customer = cart.customer;
        final Widget memberRow = !memberOn
            ? const SizedBox.shrink()
            : customer == null
                ? (askLabel
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: EdgeInsets.fromLTRB(gutter - AppSpace.s2, AppSpace.s2, gutter, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _busy ? null : _pickMember,
                            icon: const Icon(Icons.person_search_rounded),
                            label: const Text('Tambah member'),
                          ),
                        ),
                      ))
                : Padding(
                    padding: EdgeInsets.fromLTRB(gutter, askLabel ? 0 : AppSpace.s3, gutter, AppSpace.s2),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(AppSpace.s3, AppSpace.s1, AppSpace.s1, AppSpace.s1),
                      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.mdAll),
                      child: Row(
                        children: [
                          const Icon(Icons.card_membership_rounded, size: 20, color: AppColors.primaryStrong),
                          const SizedBox(width: AppSpace.s2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Flexible(
                                    child: Text(
                                      customer.name,
                                      style: AppType.caption.copyWith(color: AppColors.primaryStrong, fontWeight: FontWeight.w700),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (customer.tier != null) ...[const SizedBox(width: AppSpace.s1), TierBadge(customer.tier!, dense: true)],
                                ]),
                                if (customer.tier != null && customer.tier!.benefits.isNotEmpty)
                                  Text(
                                    '${customer.tier!.name}: ${customer.tier!.benefits}',
                                    style: AppType.caption.copyWith(color: AppColors.primaryStrong),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                Text(
                                  [
                                    'Member ${customer.code}',
                                    if (customer.visits != null) '${customer.visits}× belanja',
                                    if (program != null && customer.balance != null) '${customer.balance} ${program.unit}',
                                  ].join(' · '),
                                  style: AppType.caption.copyWith(color: AppColors.primaryStrong),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (customer.note != null && customer.note!.isNotEmpty)
                                  Text('Catatan: ${customer.note}',
                                      style: AppType.caption.copyWith(color: AppColors.warning),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                if ((customer.creditBalance ?? 0) > 0 && (menu?.feature('customer_credit') ?? false))
                                  Row(children: [
                                    Flexible(
                                      child: Text('Kasbon ${rp(customer.creditBalance!)}',
                                          style: AppType.caption.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700)),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2),
                                        minimumSize: const Size(0, 32),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: _busy ? null : _repay,
                                      child: const Text('Bayar kasbon'),
                                    ),
                                  ]),
                                if (reward != null)
                                  Text('Hadiah: ${reward.name} (−${reward.cost} ${program?.unit ?? 'stempel'})',
                                      style: AppType.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis)
                                else if (program != null && program.rewards.isNotEmpty && !cart.isEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 36),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: _busy ? null : _pickReward,
                                      icon: const Icon(Icons.redeem_rounded, size: 18),
                                      label: const Text('Tukar hadiah'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: reward != null ? 'Batalkan hadiah' : 'Lepas member',
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy ? null : (reward != null ? notifier.clearReward : notifier.clearCustomer),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                  );

        Widget line(int i) {
          final l = cart.lines[i];
          final discount = totals.lineDiscounts.length > i ? totals.lineDiscounts[i] : 0;
          final isReward = l.id == cart.rewardItemId;
          // Diskon otomatis (promo / tingkat member) diberi nama sumbernya.
          final auto = isReward || menu == null ? null : lineBenefit(cart, menu, l, DateTime.now());
          final meta = [
            if (l.modifiers.isNotEmpty) modifierSummary(l.modifiers),
            if (l.note != null && l.note!.isNotEmpty) '“${l.note}”',
          ].join(' · ');
          return InkWell(
            onTap: () => _editLine(l, canDiscount && !isReward),
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
                            '${isReward ? 'Hadiah' : auto?.label ?? 'Diskon'} -${rupiah(discount)}',
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
            AppSummaryRow(reward != null && !reward.isFreeProduct
                ? 'Hadiah: ${reward.name}'
                : cart.voucher != null ? 'Voucher ${cart.voucher!.code}' : 'Diskon',
                '-${rupiah(totals.orderDiscount)}', valueColor: AppColors.success),
          if (totals.serviceTotal > 0)
            AppSummaryRow(withRate('Service', menu?.pricing.serviceBp, included: menu?.pricing.serviceInclusive ?? false),
                rupiah(totals.serviceTotal)),
          if (totals.taxTotal > 0)
            AppSummaryRow(withRate('Pajak', menu?.pricing.taxBp, included: menu?.pricing.taxInclusive ?? false),
                rupiah(totals.taxTotal)),
          if (totals.rounding != 0) AppSummaryRow('Pembulatan', rupiah(totals.rounding)),
          if (program != null && earn > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                const Icon(Icons.loyalty_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: AppSpace.s1),
                Expanded(
                  child: Text('${program.name}: dapat +$earn ${program.unit}',
                      style: AppType.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          // Hadiah potongan memakai diskon order: diskon order manual tidak bisa digabung.
          if (cart.voucher != null) ...[
            Row(children: [
              Expanded(
                child: Text(
                  totals.orderDiscount > 0
                      ? 'Voucher ${cart.voucher!.code} terpasang'
                      : 'Voucher ${cart.voucher!.code}: minimal belanja ${rp(cart.voucher!.minSpend)}',
                  style: AppType.caption.copyWith(color: totals.orderDiscount > 0 ? AppColors.success : AppColors.warning),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 32), visualDensity: VisualDensity.compact),
                onPressed: _busy ? null : notifier.clearVoucher,
                child: const Text('Lepas voucher'),
              ),
            ]),
          ] else if ((menu?.feature('promotions') ?? false) && !cart.isEmpty && cart.orderDiscount == null && (reward == null || reward.isFreeProduct))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                onPressed: _busy
                    ? null
                    : () async {
                        final v = await showVoucherDialog(context);
                        if (v != null) notifier.setVoucher(v);
                      },
                icon: const Icon(Icons.confirmation_number_rounded, size: 18),
                label: const Text('Pakai voucher'),
              ),
            ),
          if (canDiscount && !cart.isEmpty && cart.voucher == null && (reward == null || reward.isFreeProduct))
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
        // Chip member (catatan, hadiah) menambah tinggi bagian atas → lebih cepat beralih ke susunan scroll.
        final short = box.maxHeight < (customer != null && memberOn ? 660 : 560);
        final body = short
            ? ListView(
                padding: EdgeInsets.zero,
                children: [
                  header,
                  if (askLabel) labelField,
                  memberRow,
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
                  if (askLabel) labelField,
                  memberRow,
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
