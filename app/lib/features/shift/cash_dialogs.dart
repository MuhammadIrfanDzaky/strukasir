import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../cart/dialogs.dart' show ApprovalDialog;
import '../cart/order_api.dart' show Approval;
import '../session/session_controller.dart';
import '../../core/ui/toast.dart';

final cashApiProvider = Provider((ref) => CashApi(ref));

/// Kas keluar / masuk di luar penjualan (shift terbuka tablet ini).
class CashApi {
  CashApi(this._ref);

  final Ref _ref;

  Future<T> _authed<T>(Future<T> Function(ApiClient api, String token) call) =>
      _ref.read(sessionProvider.notifier).authed(call);

  /// (catatan shift ini, kategori [{kind, key, label, expense}])
  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> list() async {
    final res = await _authed((api, token) => api.get('/shifts/current/cash-movements', token: token));
    return (
      (res['data'] as List).cast<Map<String, dynamic>>(),
      (res['categories'] as List).cast<Map<String, dynamic>>(),
    );
  }

  Future<void> record({required String id, required String kind, required String category, required int amount, String? note}) =>
      _authed((api, token) => api.post('/shifts/current/cash-movements', token: token, data: {
            'id': id,
            'kind': kind,
            'category': category,
            'amount': amount,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }));

  Future<void> cancel(String id, String reason, {Approval? approval}) => _authed((api, token) => api.post('/cash-movements/$id/cancel',
      token: token,
      data: {
        'reason': reason,
        if (approval != null) 'approval': {'user_id': approval.userId, 'pin': approval.pin},
      }));
}

/// Catat kas keluar ([kind] = 'out') atau masuk ('in'). True bila tersimpan.
Future<bool> showCashDialog(BuildContext context, {required String kind}) async =>
    await showDialog<bool>(context: context, builder: (_) => _CashDialog(kind: kind)) ?? false;

class _CashDialog extends ConsumerStatefulWidget {
  const _CashDialog({required this.kind});

  final String kind;

  @override
  ConsumerState<_CashDialog> createState() => _CashDialogState();
}

class _CashDialogState extends ConsumerState<_CashDialog> {
  final _id = const Uuid().v4(); // sekali per dialog: tombol ditekan ulang tidak dobel
  final _amount = TextEditingController();
  final _note = TextEditingController();
  List<Map<String, dynamic>>? _categories;
  String? _category;
  String? _error;
  bool _busy = false;

  bool get _out => widget.kind == 'out';

  @override
  void initState() {
    super.initState();
    ref.read(cashApiProvider).list().then((r) {
      if (!mounted) return;
      setState(() {
        _categories = r.$2.where((c) => c['kind'] == widget.kind).toList();
        _category = _categories!.first['key'] as String;
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseRupiah(_amount.text);
    if (amount == null || amount <= 0 || _category == null) {
      setState(() => _error = 'Isi nominal');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(cashApiProvider).record(id: _id, kind: widget.kind, category: _category!, amount: amount, note: _note.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    return AlertDialog(
      scrollable: true,
      title: Text(_out ? 'Kas keluar' : 'Kas masuk'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            _out
                ? 'Uang yang diambil dari laci di luar penjualan, mis. beli es batu, gas, upah harian, setor ke owner.'
                : 'Uang yang ditambahkan ke laci di luar penjualan, mis. tambah uang kecil untuk kembalian.',
            style: AppType.body.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpace.s3),
          if (categories == null && _error == null)
            const Padding(padding: EdgeInsets.all(AppSpace.s4), child: Center(child: CircularProgressIndicator()))
          else if (categories != null)
            Wrap(spacing: AppSpace.s2, runSpacing: AppSpace.s2, children: [
              for (final c in categories)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(c['label'] as String),
                  selected: _category == c['key'],
                  onSelected: _busy ? null : (_) => setState(() => _category = c['key'] as String),
                ),
            ]),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp '),
          ),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _note,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Keterangan (opsional)', hintText: 'mis. es batu 2 kantong'),
          ),
          if (_error != null) Text(_error!, style: AppType.caption.copyWith(color: AppColors.danger)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(
          onPressed: _busy || categories == null ? null : _save,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Daftar kas keluar/masuk shift ini, dengan pembatalan (kasir butuh PIN owner).
Future<void> showCashListDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _CashList());

class _CashList extends ConsumerStatefulWidget {
  const _CashList();

  @override
  ConsumerState<_CashList> createState() => _CashListState();
}

class _CashListState extends ConsumerState<_CashList> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(cashApiProvider).list();
      if (mounted) setState(() => _rows = r.$1);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _cancel(Map<String, dynamic> row) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan catatan kas?'),
        content: TextField(controller: reason, autofocus: true, decoration: const InputDecoration(labelText: 'Alasan', hintText: 'mis. salah ketik nominal')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Tidak')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Batalkan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final why = reason.text.trim().length < 3 ? 'Salah catat' : reason.text.trim();
    Approval? approval;
    while (mounted) {
      try {
        await ref.read(cashApiProvider).cancel(row['id'] as String, why, approval: approval);
        _load();
        return;
      } on ApiException catch (e) {
        if (e.field('approval') == null) {
          if (mounted) AppToast.of(context).showSnackBar(SnackBar(content: Text(e.message)));
          return;
        }
        if (!mounted) return;
        approval = await showDialog<Approval>(context: context, builder: (_) => ApprovalDialog(reason: 'Batalkan catatan kas. ${e.field('approval')}'));
        if (approval == null) return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final out = rows?.where((r) => r['kind'] == 'out' && r['cancelled'] != true).fold<int>(0, (s, r) => s + (r['amount'] as int)) ?? 0;
    final inn = rows?.where((r) => r['kind'] == 'in' && r['cancelled'] != true).fold<int>(0, (s, r) => s + (r['amount'] as int)) ?? 0;
    return AlertDialog(
      scrollable: true,
      title: const Text('Kas keluar / masuk shift ini'),
      content: SizedBox(
        width: 460,
        child: rows == null
            ? (_error == null ? const Center(child: CircularProgressIndicator()) : Text(_error!))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppSummaryRow('Total keluar', rp(out)),
                AppSummaryRow('Total masuk', rp(inn)),
                const Divider(),
                if (rows.isEmpty) Text('Belum ada catatan.', style: AppType.body.copyWith(color: AppColors.inkMuted)),
                for (final r in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${r['kind'] == 'out' ? '−' : '+'}${rp(r['amount'] as int)} · ${r['category_label']}',
                      style: AppType.bodyStrong.copyWith(
                        decoration: r['cancelled'] == true ? TextDecoration.lineThrough : null,
                        color: r['cancelled'] == true ? AppColors.inkDisabled : null,
                      ),
                    ),
                    subtitle: Text(
                      [
                        _time(r['created_at'] as String),
                        if (r['user'] != null) r['user'] as String,
                        if (r['note'] != null) r['note'] as String,
                        if (r['cancelled'] == true) 'dibatalkan',
                      ].join(' · '),
                      style: AppType.caption.copyWith(color: AppColors.inkMuted),
                    ),
                    trailing: r['cancelled'] == true
                        ? null
                        : IconButton(tooltip: 'Batalkan', onPressed: () => _cancel(r), icon: const Icon(Icons.undo_rounded)),
                  ),
              ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
    );
  }

  static String _time(String iso) {
    final t = DateTime.parse(iso).toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
