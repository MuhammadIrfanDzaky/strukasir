import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../session/session_controller.dart';
import 'promotion_models.dart';

/// Kasir memasukkan kode voucher; server memeriksa (aktif, tanggal, kuota) dan mengembalikan syaratnya.
Future<VoucherTerms?> showVoucherDialog(BuildContext context) =>
    showDialog<VoucherTerms>(context: context, builder: (_) => const _VoucherDialog());

class _VoucherDialog extends ConsumerStatefulWidget {
  const _VoucherDialog();

  @override
  ConsumerState<_VoucherDialog> createState() => _VoucherDialogState();
}

class _VoucherDialogState extends ConsumerState<_VoucherDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final code = _code.text.trim();
    if (code.isEmpty) return setState(() => _error = 'Isi kode voucher');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(sessionProvider.notifier).authed(
            (api, token) => api.get('/vouchers/check?code=${Uri.encodeQueryComponent(code)}', token: token),
          );
      final v = VoucherTerms.fromJson(res['data'] as Map<String, dynamic>);
      if (mounted) Navigator.pop(context, v);
    } on ApiException catch (e) {
      setState(() => _error = e.field('voucher_code') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Pakai voucher'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _check(),
              decoration: InputDecoration(labelText: 'Kode voucher', hintText: 'mis. HEMAT10', errorText: _error),
            ),
            const SizedBox(height: AppSpace.s2),
            Text('Voucher tidak bisa digabung dengan diskon order atau hadiah potongan.',
                style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: _busy ? null : _check,
            child: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Pakai'),
          ),
        ],
      );
}

/// Ringkasan syarat voucher untuk ditampilkan, mis. "Diskon 10% (maks. Rp 5.000) · min. Rp 30.000".
String voucherSummary(VoucherTerms v) => [v.effect, if (v.minSpend > 0) 'min. ${rp(v.minSpend)}'].join(' · ');
