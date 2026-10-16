import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import '../session/session_controller.dart';
import '../subscription/locked_feature.dart';
import '../../core/ui/toast.dart';

/// Outlet / cabang usaha (fitur `multi_outlet`).
class Outlet {
  const Outlet({required this.id, required this.code, required this.name, this.address, this.phone, this.active = true, this.devices = const []});

  factory Outlet.fromJson(Map<String, dynamic> j) => Outlet(
    id: j['id'] as String,
    code: j['code'] as String? ?? '',
    name: j['name'] as String,
    address: j['address'] as String?,
    phone: j['phone'] as String?,
    active: j['active'] as bool? ?? true,
    devices: ((j['devices'] as List?) ?? const []).cast<Map<String, dynamic>>(),
  );

  final String id;
  final String code;
  final String name;
  final String? address;
  final String? phone;
  final bool active;

  /// Tablet di outlet ini: id, code, name, last_seen_at, current (tablet yang sedang dipakai).
  final List<Map<String, dynamic>> devices;
}

/// Daftar outlet + status fitur (owner). Dipakai layar Outlet, filter dashboard, dan stok.
final outletsProvider = FutureProvider.autoDispose<({bool enabled, List<Outlet> outlets})>((ref) async {
  final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.get('/outlets', token: token));
  final data = res['data'] as Map<String, dynamic>;
  return (enabled: data['enabled'] as bool? ?? false, outlets: (data['outlets'] as List).cast<Map<String, dynamic>>().map(Outlet.fromJson).toList());
});

/// Pilihan outlet ringkas (dashboard, stok). [allLabel] != null → ada pilihan "semua outlet" (nilai null).
class OutletPicker extends ConsumerWidget {
  const OutletPicker({super.key, required this.value, required this.onChanged, this.allLabel, this.maxWidth = 200});

  final double maxWidth;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? allLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlets = ref.watch(outletsProvider).value?.outlets.where((o) => o.active).toList();
    if (outlets == null || outlets.length < 2) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          isExpanded: true,
          borderRadius: AppRadius.mdAll,
          items: [
            if (allLabel != null) DropdownMenuItem<String?>(value: null, child: Text(allLabel!)),
            for (final o in outlets)
              DropdownMenuItem<String?>(
                value: o.id,
                child: Text(o.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Pengaturan → Outlet (owner): daftar outlet & tabletnya, tambah/ubah outlet, pindah tablet.
class OutletsScreen extends ConsumerWidget {
  const OutletsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Outlet? outlet]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _OutletForm(outlet: outlet),
    );
    if (saved == true) {
      ref.invalidate(outletsProvider);
      ref.read(menuProvider.notifier).refresh(); // nama/alamat outlet di struk
    }
  }

  Future<void> _move(BuildContext context, WidgetRef ref, Map<String, dynamic> device, Outlet from, List<Outlet> outlets) async {
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Pindahkan ${device['name']}'),
        children: [
          for (final o in outlets.where((o) => o.active && o.id != from.id))
            SimpleDialogOption(onPressed: () => Navigator.pop(context, o.id), child: Text(o.name)),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    final messenger = AppToast.of(context);
    try {
      await ref.read(sessionProvider.notifier).authed((api, token) => api.put('/devices/${device['id']}/outlet', token: token, data: {'outlet_id': target}));
      ref.invalidate(outletsProvider);
      if (device['current'] == true) ref.read(menuProvider.notifier).refresh();
      messenger.showSnackBar(SnackBar(content: Text('${device['name']} dipindahkan.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Keluarkan tablet lain (hilang, rusak, aplikasinya di-reset): kuota tablet paket kembali.
  Future<void> _revoke(BuildContext context, WidgetRef ref, Map<String, dynamic> device) async {
    final seen = DateTime.tryParse(device['last_seen_at'] as String? ?? '')?.toLocal();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Keluarkan ${device['code']} · ${device['name']}?'),
        content: Text(
          '${seen == null ? 'Belum pernah dipakai.' : 'Terakhir aktif ${_ago(seen)}.'} '
          'Semua sesi di tablet itu langsung berakhir dan kuota tablet paket kembali. Data transaksi tetap aman. '
          'Untuk memakainya lagi, daftarkan ulang dengan akun owner.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluarkan'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = AppToast.of(context);
    try {
      await ref.read(sessionProvider.notifier).authed((api, token) => api.post('/devices/${device['id']}/revoke', token: token));
      ref.invalidate(outletsProvider);
      messenger.showSnackBar(SnackBar(content: Text('${device['code']} dikeluarkan dari usaha.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message)));
    }
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'baru saja';
    if (d.inHours < 1) return '${d.inMinutes} menit lalu';
    if (d.inDays < 1) return '${d.inHours} jam lalu';
    return '${d.inDays} hari lalu';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(outletsProvider);
    final multiLock = ref.watch(menuProvider).value?.menu.locked('multi_outlet');
    final pad = context.isCompact ? AppSpace.s3 : AppSpace.s5;
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Outlet')),
      body: async.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorState(message: e is ApiException ? e.message : '$e', onRetry: () => ref.invalidate(outletsProvider)),
        data: (d) => ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 96),
          children: [
            Text(
              'Menu, pelanggan, promo, dan staf sama untuk semua outlet. Shift, transaksi, open bill, dan stok bahan '
              'terpisah per outlet; laporan bisa dilihat per outlet atau gabungan.',
              style: AppType.body.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpace.s3),
            for (final o in d.outlets)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(o.name, style: AppType.title.copyWith(color: o.active ? null : AppColors.inkMuted)),
                          ),
                          AppBadge(o.code),
                          if (!o.active) ...[const SizedBox(width: AppSpace.s1), const AppBadge('Nonaktif')],
                          IconButton(tooltip: 'Ubah outlet', onPressed: () => _edit(context, ref, o), icon: const Icon(Icons.edit_rounded)),
                        ],
                      ),
                      if (o.address != null || o.phone != null) Text([?o.address, if (o.phone != null) 'Telp. ${o.phone}'].join(' · '), style: muted),
                      const SizedBox(height: AppSpace.s2),
                      if (o.devices.isEmpty)
                        Text('Belum ada tablet. Daftarkan tablet baru dengan akun owner lalu pilih outlet ini.', style: muted)
                      else
                        Wrap(
                          spacing: AppSpace.s2,
                          runSpacing: AppSpace.s2,
                          children: [
                            for (final dev in o.devices)
                              // Ketuk = pindah outlet (bila > 1 outlet); × = keluarkan (bukan tablet ini).
                              InputChip(
                                label: Text('${dev['code']} · ${dev['name']}${dev['current'] == true ? ' (tablet ini)' : ''}'),
                                onPressed: d.outlets.where((x) => x.active).length < 2 ? null : () => _move(context, ref, dev, o, d.outlets),
                                onDeleted: dev['current'] == true ? null : () => _revoke(context, ref, dev),
                                deleteIcon: const Icon(Icons.close_rounded, size: 18),
                                deleteButtonTooltipMessage: 'Keluarkan tablet',
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpace.s3),
            if (!d.enabled && multiLock == null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s2),
                child: Text(
                  'Aktifkan fitur Multi-outlet (Pengaturan → Fitur) untuk menambah outlet.',
                  style: AppType.body.copyWith(color: AppColors.warning),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: d.enabled || multiLock == null
                  ? FilledButton(onPressed: d.enabled ? () => _edit(context, ref) : null, child: const Text('Tambah outlet'))
                  // Di luar paket: tombol tetap ada, terkunci → ajakan upgrade.
                  : OutlinedButton.icon(
                      onPressed: () => showLockedFeature(context, multiLock),
                      icon: const Icon(Icons.lock_rounded, size: 18, color: AppColors.warning),
                      label: Text('Tambah outlet · paket ${multiLock.planName}'),
                    ),
            ),
            const SizedBox(height: AppSpace.s2),
            Text('Tablet yang hilang, rusak, atau aplikasinya di-reset: tekan × untuk mengeluarkannya agar kuota tablet kembali.',
                style: muted),
            if (d.outlets.where((x) => x.active).length > 1) ...[
              const SizedBox(height: AppSpace.s2),
              Text('Ketuk tablet untuk memindahkannya ke outlet lain (shift tablet harus sudah ditutup).', style: muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _OutletForm extends ConsumerStatefulWidget {
  const _OutletForm({this.outlet});

  final Outlet? outlet;

  @override
  ConsumerState<_OutletForm> createState() => _OutletFormState();
}

class _OutletFormState extends ConsumerState<_OutletForm> {
  late final _name = TextEditingController(text: widget.outlet?.name ?? '');
  late final _address = TextEditingController(text: widget.outlet?.address ?? '');
  late final _phone = TextEditingController(text: widget.outlet?.phone ?? '');
  late bool _active = widget.outlet?.active ?? true;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final o = widget.outlet;
    final data = {
      'name': _name.text.trim(),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'active': _active,
    };
    try {
      await ref
          .read(sessionProvider.notifier)
          .authed((api, token) => o == null ? api.post('/outlets', token: token, data: data) : api.put('/outlets/${o.id}', token: token, data: data));
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.outlet == null ? 'Tambah outlet' : 'Ubah outlet'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nama outlet', hintText: 'mis. BerryBrew Dago', counterText: ''),
          ),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _address,
            maxLength: 160,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Alamat (dicetak di struk outlet ini)', counterText: ''),
          ),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _phone,
            maxLength: 20,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telepon (opsional)', counterText: ''),
          ),
          if (widget.outlet != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Aktif'),
              subtitle: const Text('Outlet nonaktif tidak bisa dipilih tablet; riwayatnya tetap tersimpan.'),
            ),
          if (_error != null) Text(_error!, style: AppType.caption.copyWith(color: AppColors.danger)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
      FilledButton(onPressed: _busy ? null : _submit, child: const Text('Simpan')),
    ],
  );
}
