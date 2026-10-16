import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import '../session/session_controller.dart';
import 'member_tier.dart';
import '../../core/ui/toast.dart';

const _windows = [null, 3, 6, 12, 24];

/// Pengaturan → Tingkat member (owner): dasar kenaikan, jendela waktu, daftar tingkat & manfaatnya.
class TierSettingsScreen extends ConsumerStatefulWidget {
  const TierSettingsScreen({super.key});

  @override
  ConsumerState<TierSettingsScreen> createState() => _TierSettingsScreenState();
}

class _TierSettingsScreenState extends ConsumerState<TierSettingsScreen> {
  bool _loaded = false;
  String? _loadError;
  String? _error;
  bool _busy = false;
  String _basis = 'spend';
  int? _window = 12;
  final List<MemberTier> _tiers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.get('/settings/tiers', token: token));
      _apply(res['data'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      setState(() => _loadError = e.message);
    }
  }

  void _apply(Map<String, dynamic> data) => setState(() {
        _loaded = true;
        _basis = data['basis'] as String? ?? 'spend';
        _window = data['window_months'] as int?;
        _tiers
          ..clear()
          ..addAll((data['tiers'] as List).cast<Map<String, dynamic>>().map(MemberTier.fromJson));
      });

  String _threshold(int v) => _basis == 'visits' ? '$v kunjungan' : rp(v);

  Future<void> _edit([int? index]) async {
    final tier = await showDialog<MemberTier>(
      context: context,
      builder: (_) => _TierForm(basis: _basis, tier: index == null ? null : _tiers[index], suggestedColor: _suggestColor()),
    );
    if (tier == null) return;
    setState(() {
      index == null ? _tiers.add(tier) : _tiers[index] = tier;
      _tiers.sort((a, b) => a.threshold.compareTo(b.threshold));
    });
  }

  String _suggestColor() => const ['bronze', 'silver', 'gold', 'platinum', 'indigo'][_tiers.length.clamp(0, 4)];

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.put('/settings/tiers', token: token, data: {
            'basis': _basis,
            'window_months': _window,
            'tiers': [
              for (final t in _tiers)
                {
                  if (t.id.isNotEmpty) 'id': t.id,
                  'name': t.name,
                  'threshold': t.threshold,
                  'discount_bp': t.discountBp,
                  'earn_multiplier': t.earnMultiplier,
                  'color': t.color,
                },
            ],
          }));
      _apply(res['data'] as Map<String, dynamic>);
      await ref.read(menuProvider.notifier).refresh();
      if (!mounted) return;
      AppToast.of(context).showSnackBar(const SnackBar(content: Text('Tingkat member disimpan. Semua tablet ikut berubah.')));
      Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      setState(() => _error = e.fieldErrors.isEmpty ? e.message : e.fieldErrors.values.first.first);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.surfaceApp,
        appBar: AppBar(title: const Text('Tingkat member')),
        body: !_loaded
            ? (_loadError == null ? const AppLoading() : AppErrorState(message: _loadError!, onRetry: _load))
            : ListView(
                padding: EdgeInsets.all(context.isCompact ? AppSpace.s3 : AppSpace.s5),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(
                          'Member naik tingkat otomatis dari belanjanya, dan turun lagi bila tidak aktif. '
                          'Owner tetap bisa mengunci tingkat seseorang dari halaman pelanggan.',
                          style: AppType.body.copyWith(color: AppColors.inkMuted),
                        ),
                        const SizedBox(height: AppSpace.s3),
                        AppSectionCard(title: 'Cara naik tingkat', children: [
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 'spend', label: Text('Total belanja'), icon: Icon(Icons.payments_rounded)),
                              ButtonSegment(value: 'visits', label: Text('Jumlah kunjungan'), icon: Icon(Icons.repeat_rounded)),
                            ],
                            selected: {_basis},
                            onSelectionChanged: _busy
                                ? null
                                : (v) => setState(() {
                                      // Ambang beda satuan (Rp ↔ kali): hapus supaya diisi ulang.
                                      if (v.first != _basis && _tiers.isNotEmpty) _tiers.clear();
                                      _basis = v.first;
                                    }),
                          ),
                          const SizedBox(height: AppSpace.s3),
                          DropdownButtonFormField<int?>(
                            initialValue: _window,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Dihitung dari', isDense: true),
                            items: [
                              for (final w in _windows)
                                DropdownMenuItem(value: w, child: Text(w == null ? 'Sepanjang waktu' : '$w bulan terakhir')),
                            ],
                            onChanged: _busy ? null : (v) => setState(() => _window = v),
                          ),
                        ]),
                        const SizedBox(height: AppSpace.s3),
                        AppSectionCard(
                          title: 'Tingkat',
                          trailing: TextButton(onPressed: _busy || _tiers.length >= 6 ? null : () => _edit(), child: const Text('Tambah'), ),
                          empty: 'Belum ada tingkat. Contoh: Silver (belanja Rp500.000) diskon 5%, Gold (Rp2.000.000) diskon 10% & stempel 2×.',
                          children: [
                            for (final (i, t) in _tiers.indexed)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: TierBadge(t),
                                title: Text('Mulai ${_threshold(t.threshold)}', style: AppType.bodyStrong),
                                subtitle: Text(t.benefits.isEmpty ? 'Tanpa manfaat (lencana saja)' : t.benefits,
                                    style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                                onTap: _busy ? null : () => _edit(i),
                                trailing: IconButton(
                                  tooltip: 'Hapus tingkat',
                                  onPressed: _busy ? null : () => setState(() => _tiers.removeAt(i)),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpace.s3),
                          Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
                        ],
                        const SizedBox(height: AppSpace.s5),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
                          child: _busy
                              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : const Text('Simpan'),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
      );
}

class _TierForm extends StatefulWidget {
  const _TierForm({required this.basis, this.tier, required this.suggestedColor});

  final String basis;
  final MemberTier? tier;
  final String suggestedColor;

  @override
  State<_TierForm> createState() => _TierFormState();
}

class _TierFormState extends State<_TierForm> {
  late final _name = TextEditingController(text: widget.tier?.name ?? '');
  late final _threshold = TextEditingController(
      text: widget.tier == null ? '' : (widget.basis == 'visits' ? '${widget.tier!.threshold}' : rupiah(widget.tier!.threshold)));
  late final _discount = TextEditingController(
      text: widget.tier == null || widget.tier!.discountBp == 0 ? '' : percentBp(widget.tier!.discountBp).replaceAll('%', ''));
  late int _multiplier = widget.tier?.earnMultiplier ?? 1;
  late String _color = widget.tier?.color ?? widget.suggestedColor;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _threshold.dispose();
    _discount.dispose();
    super.dispose();
  }

  void _submit() {
    final threshold = parseRupiah(_threshold.text);
    final percent = _discount.text.trim().isEmpty ? 0.0 : double.tryParse(_discount.text.trim().replaceAll(',', '.'));
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Isi nama tingkat',
      if (threshold == null) 'threshold': 'Isi ambang',
      if (percent == null || percent < 0 || percent > 50) 'discount': 'Isi 0–50',
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    Navigator.pop(
      context,
      MemberTier(
        id: widget.tier?.id ?? '',
        name: _name.text.trim(),
        threshold: threshold!,
        discountBp: (percent! * 100).round(),
        earnMultiplier: _multiplier,
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visits = widget.basis == 'visits';
    return AlertDialog(
      scrollable: true,
      title: Text(widget.tier == null ? 'Tambah tingkat' : 'Ubah tingkat'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            maxLength: 30,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Nama tingkat', hintText: 'mis. Gold', errorText: _errors['name'], counterText: ''),
          ),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _threshold,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(
              labelText: visits ? 'Mulai dari (jumlah kunjungan)' : 'Mulai dari total belanja',
              prefixText: visits ? null : 'Rp ',
              suffixText: visits ? 'kali' : null,
              errorText: _errors['threshold'],
            ),
          ),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _discount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: 'Diskon otomatis',
              suffixText: '%',
              helperText: 'Kosongkan = tanpa diskon. Item yang sudah didiskon tidak ikut.',
              helperMaxLines: 2,
              errorText: _errors['discount'],
            ),
          ),
          const SizedBox(height: AppSpace.s3),
          Text('Pengali stempel / poin', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s1),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [for (final m in const [1, 2, 3]) ButtonSegment(value: m, label: Text('$m×'))],
            selected: {_multiplier},
            onSelectionChanged: (v) => setState(() => _multiplier = v.first),
          ),
          const SizedBox(height: AppSpace.s3),
          Text('Warna lencana', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s1),
          Wrap(spacing: AppSpace.s2, runSpacing: AppSpace.s2, children: [
            for (final e in tierColorLabels.entries)
              ChoiceChip(
                showCheckmark: false,
                selected: _color == e.key,
                onSelected: (_) => setState(() => _color = e.key),
                label: Text(e.value),
                avatar: CircleAvatar(backgroundColor: tierColors(e.key).$2, radius: 6),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _submit, child: const Text('Simpan')),
      ],
    );
  }
}
