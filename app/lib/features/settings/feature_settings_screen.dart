import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import '../session/session_controller.dart';

/// Satu fitur dari GET /settings/features.
class FeatureOption {
  const FeatureOption({
    required this.key,
    required this.label,
    required this.description,
    required this.available,
    required this.enabled,
    this.requires,
  });

  factory FeatureOption.fromJson(Map<String, dynamic> j) => FeatureOption(
        key: j['key'] as String,
        label: j['label'] as String,
        description: j['description'] as String,
        available: j['available'] as bool,
        enabled: j['enabled'] as bool,
        requires: j['requires'] as String?,
      );

  final String key;
  final String label;
  final String description;

  /// Termasuk paket kedai; bila tidak, hanya bisa dimatikan.
  final bool available;
  final bool enabled;

  /// Fitur lain yang harus aktif (mis. Open Bill butuh Nama pelanggan / meja).
  final String? requires;
}

/// Pengaturan → Fitur (owner): nyalakan/matikan modul sesuai cara berjualan. Mematikan fitur
/// tidak menghapus data; semua tablet ikut berubah setelah menu dimuat ulang.
class FeatureSettingsScreen extends ConsumerStatefulWidget {
  const FeatureSettingsScreen({super.key});

  @override
  ConsumerState<FeatureSettingsScreen> createState() => _FeatureSettingsScreenState();
}

class _FeatureSettingsScreenState extends ConsumerState<FeatureSettingsScreen> {
  List<FeatureOption>? _options;
  final Map<String, bool> _on = {};
  final _tax = TextEditingController();
  final _service = TextEditingController();

  /// Harga di menu sudah termasuk pajak / service (diatur terpisah).
  bool _taxInclusive = false;
  bool _serviceInclusive = false;

  /// Form pelanggan baru: no HP wajib.
  bool _phoneRequired = true;
  String? _loadError;
  String? _error;
  Map<String, String> _fieldErrors = {};
  bool _busy = false;

  static const _icons = {
    'customer_name': Icons.badge_rounded,
    'open_bill': Icons.receipt_long_rounded,
    'modifiers': Icons.tune_rounded,
    'discounts': Icons.percent_rounded,
    'tax_service': Icons.account_balance_rounded,
    'split_payment': Icons.call_split_rounded,
    'customers': Icons.groups_rounded,
    'loyalty': Icons.loyalty_rounded,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tax.dispose();
    _service.dispose();
    super.dispose();
  }

  static String _percent(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  void _apply(Map<String, dynamic> data) {
    final options =
        (data['features'] as List).cast<Map<String, dynamic>>().map(FeatureOption.fromJson).toList();
    setState(() {
      _options = options;
      _on
        ..clear()
        ..addAll({for (final o in options) o.key: o.enabled});
      _tax.text = _percent(data['tax_percent'] as num);
      _service.text = _percent(data['service_percent'] as num);
      _taxInclusive = data['tax_inclusive'] as bool? ?? false;
      _serviceInclusive = data['service_inclusive'] as bool? ?? false;
      _phoneRequired = data['customer_phone_required'] as bool? ?? true;
    });
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final res = await ref
          .read(sessionProvider.notifier)
          .authed((api, token) => api.get('/settings/features', token: token));
      _apply(res['data'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      setState(() => _loadError = e.message);
    }
  }

  String _labelOf(String key) => _options!.firstWhere((o) => o.key == key).label;

  /// Jaga aturan ketergantungan di layar (server tetap memeriksa ulang).
  void _toggle(FeatureOption option, bool value) {
    String? note;
    setState(() {
      _on[option.key] = value;
      if (value && option.requires != null && !(_on[option.requires] ?? false)) {
        _on[option.requires!] = true;
        note = '${_labelOf(option.requires!)} ikut dinyalakan (dibutuhkan ${option.label}).';
      }
      if (!value) {
        for (final other in _options!) {
          if (other.requires == option.key && (_on[other.key] ?? false)) {
            _on[other.key] = false;
            note = '${other.label} ikut dimatikan (butuh ${option.label}).';
          }
        }
      }
    });
    if (note != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(note!)));
    }
  }

  double? _parsePercent(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final tax = _parsePercent(_tax.text.isEmpty ? '0' : _tax.text);
    final service = _parsePercent(_service.text.isEmpty ? '0' : _service.text);
    final errors = <String, String>{
      if (tax == null || tax < 0 || tax > 100) 'tax_percent': 'Isi 0–100',
      if (service == null || service < 0 || service > 100) 'service_percent': 'Isi 0–100',
    };
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    try {
      final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.put('/settings/features',
          token: token,
          data: {
            'features': _on,
            if (_on['customers'] ?? false) 'customer_phone_required': _phoneRequired,
            if (_on['tax_service'] ?? false) ...{
              'tax_percent': tax,
              'service_percent': service,
              'tax_inclusive': _taxInclusive,
              'service_inclusive': _serviceInclusive,
            },
          }));
      _apply(res['data'] as Map<String, dynamic>);
      await ref.read(menuProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fitur disimpan. Semua tablet ikut berubah.')));
      Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      setState(() {
        _fieldErrors = {
          for (final f in e.fieldErrors.keys) f.replaceFirst('features.', ''): e.field(f)!,
        };
        _error = e.fieldErrors.isEmpty ? e.message : 'Periksa kembali pilihan yang ditandai.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Fitur')),
      body: options == null
          ? (_loadError == null
              ? const AppLoading()
              : AppErrorState(title: 'Gagal memuat fitur', message: _loadError!, onRetry: _load))
          : ListView(
              padding: EdgeInsets.all(context.isCompact ? AppSpace.s3 : AppSpace.s5),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Nyalakan hanya yang dipakai, supaya layar kasir tetap ringkas. '
                          'Mematikan fitur tidak menghapus data apa pun.',
                          style: AppType.body.copyWith(color: AppColors.inkMuted),
                        ),
                        const SizedBox(height: AppSpace.s4),
                        Card(
                          child: Column(
                            children: [
                              for (final (i, o) in options.indexed) ...[
                                if (i > 0) const Divider(height: 1),
                                _tile(o),
                                if (o.key == 'tax_service' && (_on[o.key] ?? false)) _taxFields(),
                                if (o.key == 'customers' && (_on[o.key] ?? false)) _customerFields(),
                              ],
                            ],
                          ),
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tile(FeatureOption o) {
    final on = _on[o.key] ?? false;
    final locked = !o.available && !on; // di luar paket: hanya bisa dimatikan
    final error = _fieldErrors[o.key];
    return SwitchListTile(
      value: on,
      onChanged: _busy || locked ? null : (v) => _toggle(o, v),
      secondary: Icon(_icons[o.key] ?? Icons.extension_rounded, color: on ? AppColors.primary : AppColors.inkMuted),
      title: Text(o.label, style: AppType.bodyStrong),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(o.description, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          if (locked) ...[
            const SizedBox(height: AppSpace.s1),
            // Teks biasa (bukan badge) supaya bisa terlipat di layar sempit.
            Text('Tidak termasuk paket Anda',
                style: AppType.caption.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700)),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpace.s1),
            Text(error, style: AppType.caption.copyWith(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }

  Widget _customerFields() => Padding(
        padding: EdgeInsets.fromLTRB(context.isCompact ? AppSpace.s4 : 72, 0, AppSpace.s4, AppSpace.s2),
        child: SwitchListTile(
          value: _phoneRequired,
          onChanged: _busy ? null : (v) => setState(() => _phoneRequired = v),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('No HP pelanggan wajib', style: AppType.body),
          subtitle: Text(
            _phoneRequired
                ? 'Pelanggan baru harus punya no HP (tidak dobel, siap untuk WhatsApp)'
                : 'Boleh daftar dengan nama saja; tiap pelanggan tetap dapat kode member',
            style: AppType.caption.copyWith(color: AppColors.inkMuted),
          ),
        ),
      );

  Widget _taxFields() {
    InputDecoration deco(String label, String key) => InputDecoration(
          labelText: label,
          suffixText: '%',
          helperText: '0 = tidak dipungut',
          errorText: _fieldErrors[key],
          isDense: true,
        );
    final formatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    bool positive(TextEditingController c) => (_parsePercent(c.text) ?? 0) > 0;
    // Saklar "termasuk harga" hanya untuk tarif yang diisi (tidak semua kedai memungut service).
    Widget inclusive(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
          value: value,
          onChanged: _busy ? null : onChanged,
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: AppType.body),
          subtitle: Text(
            value ? 'Total = harga menu; struk menulis "Termasuk …"' : 'Ditambahkan di atas harga menu',
            style: AppType.caption.copyWith(color: AppColors.inkMuted),
          ),
        );
    final tax = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _tax,
        decoration: deco('Pajak (PB1)', 'tax_percent'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: formatters,
        onChanged: (_) => setState(() {}),
      ),
      if (positive(_tax))
        inclusive('Harga menu sudah termasuk pajak', _taxInclusive, (v) => setState(() => _taxInclusive = v)),
    ]);
    final service = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _service,
        decoration: deco('Service', 'service_percent'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: formatters,
        onChanged: (_) => setState(() {}),
      ),
      if (positive(_service))
        inclusive('Harga menu sudah termasuk service', _serviceInclusive, (v) => setState(() => _serviceInclusive = v)),
    ]);
    // Layar sempit: kolom bertumpuk supaya label & tanda % tidak terpotong.
    final compact = context.isCompact;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? AppSpace.s4 : 72, 0, AppSpace.s4, AppSpace.s4),
      child: compact
          ? Column(children: [tax, const SizedBox(height: AppSpace.s3), service])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: tax), const SizedBox(width: AppSpace.s3), Expanded(child: service)],
            ),
    );
  }
}
