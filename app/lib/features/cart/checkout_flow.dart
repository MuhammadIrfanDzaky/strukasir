import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../customers/messaging.dart';
import '../menu/menu_controller.dart';
import '../printing/printer_service.dart';
import '../printing/receipt_format.dart';
import '../shift/shift_controller.dart';
import '../shift/shift_dialogs.dart';
import 'cart_controller.dart';
import 'dialogs.dart';
import 'order_api.dart';
import 'payment_dialog.dart';

/// Alur kasir: simpan → (bayar) → cetak. Prinsip:
/// - Uang tidak pernah "hilang": ID order & pembayaran dibuat tablet, kirim ulang aman.
/// - Gagal cetak TIDAK membatalkan transaksi; struk bisa dicetak ulang (perbaikan bug Kloa).
class CheckoutFlow {
  CheckoutFlow(this.ref, this.context);

  final WidgetRef ref;
  final BuildContext context;

  OrderApi get _api => ref.read(orderApiProvider);

  /// Open Bill: simpan order sebagai belum dibayar (tanpa cetak) lalu kosongkan keranjang.
  /// Order bisa dibuka lagi dari daftar Open Bill untuk tambah pesanan atau dibayar (Close Bill).
  Future<void> openBill() async {
    final order = await _save();
    if (order == null) return;
    ref.read(cartProvider.notifier).clear();
    _snack('Open Bill ${order['number']} disimpan. Buka lagi dari daftar Open Bill.');
  }

  /// Close Bill: simpan → pilih pembayaran → bayar → cetak struk pelanggan.
  Future<void> pay() async {
    final saved = await _save();
    if (saved == null || !context.mounted) return;

    // Uang hanya boleh bergerak di shift terbuka (server juga menolaknya).
    final shift = await ref.read(shiftProvider.future).catchError((_) => null);
    if (shift == null) {
      if (!context.mounted || !await showOpenShiftDialog(context, ref)) return;
    }
    if (!context.mounted) return;

    final total = saved['grand_total'] as int;
    var payments = <PaymentDraft>[];
    if (total > 0) {
      final menu = ref.read(menuProvider).value?.menu;
      final chosen = await showDialog<List<PaymentDraft>>(
        context: context,
        builder: (_) => PaymentDialog(
          total: total,
          splitEnabled: menu?.feature('split_payment') ?? false,
          number: saved['number'] as String,
          // Kasbon hanya untuk member, bila fitur aktif.
          creditCustomer: (menu?.feature('customer_credit') ?? false) ? ref.read(cartProvider).customer : null,
        ),
      );
      if (chosen == null) return; // dibatalkan; order tetap terbuka & keranjang utuh
      payments = chosen;
    }

    OrderJson paid;
    Approval? approval;
    try {
      while (true) {
        try {
          paid = await _api.pay(saved['id'] as String, payments, total, approval: approval);
          break;
        } on ApiException catch (e) {
          // Kasbon melewati batas: minta PIN owner lalu kirim ulang (ID pembayaran sama → aman).
          if (e.field('approval') == null || !context.mounted) rethrow;
          if (approval != null) _snack(e.field('approval')!);
          approval = await showDialog<Approval>(context: context, builder: (_) => ApprovalDialog(reason: e.field('approval')!));
          if (approval == null) return;
        }
      }
    } on ApiException catch (e) {
      // 409 bisa berarti pembayaran sebelumnya sebenarnya sudah masuk (koneksi putus setelah sukses).
      final current = e.status == 409 ? await _tryGet(saved['id'] as String) : null;
      if (current?['status'] != 'paid') {
        _snack(e.message);
        return;
      }
      paid = current!;
    }

    // Struk digital via WA: hanya bila fitur aktif & member punya no HP (dicatat sebelum keranjang dikosongkan).
    final member = ref.read(cartProvider).customer;
    final canWhatsApp = (ref.read(menuProvider).value?.menu.feature('customer_messaging') ?? false) && member?.phone != null;
    ref.read(cartProvider.notifier).clear();
    await _print(paid);
    if (context.mounted) await _showDone(paid, whatsAppTo: canWhatsApp ? member!.id : null);
  }

  Future<void> reprint(OrderJson order) => _print(order);

  // ───────────────────────────── internal ─────────────────────────────

  Future<OrderJson?> _save({Approval? approval}) async {
    final cart = ref.read(cartProvider);
    final total = ref.read(cartTotalsProvider).grandTotal;
    if (cart.isEmpty) return null;

    try {
      final order = await _api.save(cart, total, approval: approval);
      ref.read(cartProvider.notifier).markSaved(order['number'] as String);
      return order;
    } on ApiException catch (e) {
      if (e.field('approval') != null && context.mounted) {
        if (approval != null) _snack(e.field('approval')!);
        final next = await showDialog<Approval>(
          context: context,
          builder: (_) => ApprovalDialog(reason: 'Diskon melebihi batas kasir. ${approval == null ? '' : e.field('approval')!}'),
        );
        return next == null ? null : _save(approval: next);
      }
      if (e.field('expected_total') != null) {
        await ref.read(menuProvider.notifier).refresh();
        _snack('Harga menu berubah. Menu sudah diperbarui — periksa total lalu coba lagi.');
        return null;
      }
      _snack(e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message);
      return null;
    }
  }

  Future<OrderJson?> _tryGet(String id) async {
    try {
      return await _api.get(id);
    } on ApiException {
      return null;
    }
  }

  /// Cetak struk pelanggan + logo kedai (dari cache menu, jadi tetap ada saat offline).
  Future<void> _print(OrderJson order) async {
    try {
      await ref.read(printerProvider.notifier).printDocument(
            customerReceipt(order),
            logoBase64: ref.read(menuProvider).value?.menu.receipt.logoBase64,
          );
    } on PrintException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        content: Text('Transaksi tersimpan, tapi struk gagal dicetak: ${e.message}'),
        action: SnackBarAction(label: 'Cetak ulang', onPressed: () => _print(order)),
      ));
    }
  }

  Future<void> _showDone(OrderJson order, {String? whatsAppTo}) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          scrollable: true,
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AppColors.successSoft, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 36, color: AppColors.success),
              ),
              const SizedBox(height: AppSpace.s3),
              Text(order['credit'] == null ? 'Lunas' : 'Kasbon dicatat', style: AppType.titleLg),
              if (order['credit'] case {'balance': final int balance})
                Text('Sisa kasbon ${rp(balance)}', style: AppType.bodyStrong.copyWith(color: AppColors.warning)),
              Text('Order ${order['number']} · Total ${rp(order['grand_total'] as int)}',
                  style: AppType.body.copyWith(color: AppColors.inkMuted)),
              if ((order['change_total'] as int) > 0) ...[
                const SizedBox(height: AppSpace.s4),
                const AppOverline('Kembalian'),
                Text(rp(order['change_total'] as int), style: AppType.display.copyWith(color: AppColors.success)),
              ],
            ]),
          ),
          actions: [
            if (whatsAppTo != null)
              TextButton.icon(
                onPressed: () => openWhatsApp(context, ref, whatsAppTo, 'receipt', orderId: order['id'] as String),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Struk via WA'),
              ),
            TextButton(onPressed: () => reprint(order), child: const Text('Cetak ulang struk')),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Order baru')),
          ],
        ),
      );

  void _snack(String message) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
