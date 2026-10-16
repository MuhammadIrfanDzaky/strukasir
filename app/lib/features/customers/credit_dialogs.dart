import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../cart/payment_dialog.dart' show suggestedCash;
import '../menu/menu_controller.dart';
import '../printing/printer_service.dart';
import '../printing/receipt_format.dart';
import '../session/session_controller.dart';
import 'customer_api.dart';
import '../../core/ui/toast.dart';

/// Catat pelunasan kasbon (kasir/owner, di shift terbuka) lalu cetak bukti. Mengembalikan sisa kasbon,
/// atau null bila dibatalkan.
Future<int?> showRepayDialog(BuildContext context, {required String customerId, required String name, required int balance}) =>
    showDialog<int>(context: context, builder: (_) => _RepayDialog(customerId: customerId, name: name, balance: balance));

class _RepayDialog extends ConsumerStatefulWidget {
  const _RepayDialog({required this.customerId, required this.name, required this.balance});

  final String customerId;
  final String name;
  final int balance;

  @override
  ConsumerState<_RepayDialog> createState() => _RepayDialogState();
}

class _RepayDialogState extends ConsumerState<_RepayDialog> {
  /// ID dibuat sekali per dialog → tombol ditekan ulang tidak mencatat dobel.
  final _id = const Uuid().v4();
  late final _amount = TextEditingController(text: rupiah(widget.balance));
  final _tendered = TextEditingController();
  String _method = 'cash';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _tendered.dispose();
    super.dispose();
  }

  int get _amountValue => parseRupiah(_amount.text) ?? 0;
  int? get _tenderedValue => parseRupiah(_tendered.text);

  String? get _problem {
    if (_amountValue <= 0) return 'Isi nominal';
    if (_amountValue > widget.balance) return 'Melebihi sisa kasbon ${rp(widget.balance)}';
    if (_method == 'cash' && (_tenderedValue ?? _amountValue) < _amountValue) return 'Uang diterima kurang';
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(customerApiProvider).repayCredit(
            widget.customerId,
            id: _id,
            method: _method,
            amount: _amountValue,
            tendered: _method == 'cash' ? (_tenderedValue ?? _amountValue) : null,
          );
      final session = ref.read(sessionProvider).value;
      try {
        await ref.read(printerProvider.notifier).printDocument(
              creditRepaymentReceipt(
                res,
                customerName: widget.name,
                cashier: session is LoggedIn ? session.user.name : null,
                shopName: ref.read(menuProvider).value?.menu.receipt.name ?? '',
              ),
              logoBase64: ref.read(menuProvider).value?.menu.receipt.logoBase64,
            );
      } on PrintException catch (e) {
        if (mounted) AppToast.of(context).showSnackBar(SnackBar(content: Text('Pelunasan tercatat, bukti gagal dicetak: ${e.message}')));
      }
      if (mounted) Navigator.pop(context, res['balance'] as int);
    } on ApiException catch (e) {
      setState(() => _error = e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final change = _method == 'cash' && (_tenderedValue ?? 0) > _amountValue ? _tenderedValue! - _amountValue : 0;
    return AlertDialog(
      scrollable: true,
      title: Text('Bayar kasbon · ${widget.name}'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSummaryRow('Sisa kasbon', rp(widget.balance), emphasis: true),
          const SizedBox(height: AppSpace.s3),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'cash', label: Text('Tunai')),
              ButtonSegment(value: 'debit', label: Text('Debit')),
              ButtonSegment(value: 'qris', label: Text('QRIS')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Dibayar', prefixText: 'Rp ', helperText: 'Boleh sebagian (cicil)'),
            onChanged: (_) => setState(() {}),
          ),
          if (_method == 'cash') ...[
            const SizedBox(height: AppSpace.s3),
            TextField(
              controller: _tendered,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Uang diterima', prefixText: 'Rp '),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpace.s2),
            Wrap(spacing: AppSpace.s2, runSpacing: AppSpace.s2, children: [
              for (final v in suggestedCash(_amountValue))
                ActionChip(
                  label: Text(v == _amountValue ? 'Uang pas' : rupiah(v)),
                  onPressed: () => setState(() => _tendered.text = rupiah(v)),
                ),
            ]),
            if (change > 0) ...[
              const SizedBox(height: AppSpace.s3),
              AppSummaryRow('Kembalian', rp(change), emphasis: true, valueColor: AppColors.success),
            ],
          ],
          if (_amountValue > 0 && _amountValue <= widget.balance) ...[
            const SizedBox(height: AppSpace.s2),
            Text('Sisa setelah ini: ${rp(widget.balance - _amountValue)}', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          ],
          if (_error != null || (problem != null && _amount.text.isNotEmpty)) ...[
            const SizedBox(height: AppSpace.s2),
            Text(_error ?? problem!, style: AppType.caption.copyWith(color: AppColors.danger)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: _busy || problem != null ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Catat pelunasan'),
        ),
      ],
    );
  }
}

/// Owner mengubah batas kasbon pelanggan: angka, tanpa batas, atau ikut default kedai.
/// Mengembalikan (diubah?, nilai) — nilai null = ikut default.
Future<(bool, int?)?> showCreditLimitDialog(BuildContext context, {required int? current, required bool custom}) =>
    showDialog<(bool, int?)>(context: context, builder: (_) => _LimitDialog(current: current, custom: custom));

class _LimitDialog extends StatefulWidget {
  const _LimitDialog({required this.current, required this.custom});

  final int? current;
  final bool custom;

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late bool _useDefault = !widget.custom;
  late final _value = TextEditingController(text: widget.current == null ? '' : rupiah(widget.current!));

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Batas kasbon'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _useDefault,
              onChanged: (v) => setState(() => _useDefault = v),
              title: const Text('Ikut batas default kedai'),
              subtitle: const Text('Diatur di Pengaturan → Fitur'),
            ),
            if (!_useDefault)
              TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Batas untuk pelanggan ini', prefixText: 'Rp ', helperText: '0 = tidak boleh kasbon'),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (true, _useDefault ? null : (parseRupiah(_value.text) ?? 0))),
            child: const Text('Simpan'),
          ),
        ],
      );
}
