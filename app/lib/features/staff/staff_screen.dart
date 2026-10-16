import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../session/session_controller.dart';
import '../../core/ui/toast.dart';

/// Pegawai di daftar Pengaturan → Pegawai.
class Staff {
  const Staff({required this.id, required this.name, required this.role, this.active = true, this.locked = false});

  factory Staff.fromJson(Map<String, dynamic> j) => Staff(
    id: j['id'] as String,
    name: j['name'] as String,
    role: j['role'] as String,
    active: j['active'] as bool? ?? true,
    locked: j['locked'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String role;
  final bool active;

  /// Terkunci sementara karena PIN salah berkali-kali (reset PIN membuka kunci).
  final bool locked;

  bool get isOwner => role == 'owner';
}

final staffListProvider = FutureProvider.autoDispose<List<Staff>>((ref) async {
  final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.get('/staff', token: token));
  return (res['data'] as List).cast<Map<String, dynamic>>().map(Staff.fromJson).toList();
});

String _firstError(ApiException e) => e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message;

/// Pengaturan → Pegawai (owner): tambah kasir, ganti nama, reset PIN, nonaktifkan.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Staff? staff]) async {
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => _StaffForm(staff: staff),
    );
    if (saved != null && context.mounted) {
      ref.invalidate(staffListProvider);
      AppToast.of(context).showSnackBar(SnackBar(content: Text(saved)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(staffListProvider);
    final pad = context.isCompact ? AppSpace.s3 : AppSpace.s5;
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Pegawai')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Tambah kasir'),
      ),
      body: async.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorState(message: e is ApiException ? e.message : '$e', onRetry: () => ref.invalidate(staffListProvider)),
        data: (list) => ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 96),
          children: [
            Text(
              'Setiap kasir masuk dengan nama & PIN sendiri, jadi transaksi, shift, dan laporan tercatat per orang. '
              'Pegawai yang berhenti dinonaktifkan (riwayatnya tetap ada).',
              style: AppType.body.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpace.s3),
            Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: const BorderSide(color: AppColors.line)),
            clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, s) in list.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 72, color: AppColors.line),
                    ListTile(
                      minVerticalPadding: AppSpace.s3,
                      onTap: s.isOwner ? null : () => _edit(context, ref, s),
                      leading: Opacity(opacity: s.active ? 1 : 0.5, child: AppAvatar(s.name, size: 40)),
                      title: Text(s.name, style: AppType.title.copyWith(color: s.active ? AppColors.ink : AppColors.inkMuted)),
                      subtitle: Text(s.isOwner ? 'Login email & password owner' : (s.active ? 'Kasir' : 'Kasir · nonaktif'), style: muted),
                      trailing: Wrap(
                        spacing: AppSpace.s1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (s.isOwner) const AppBadge('Owner', tone: AppTone.brand),
                          if (!s.active) const AppBadge('Nonaktif'),
                          if (s.locked) const AppBadge('Terkunci', tone: AppTone.danger),
                          if (!s.isOwner) const Icon(Icons.chevron_right_rounded, color: AppColors.inkDisabled),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tambah kasir (nama + PIN) atau ubah kasir (nama, aktif, PIN baru opsional).
class _StaffForm extends ConsumerStatefulWidget {
  const _StaffForm({this.staff});

  final Staff? staff;

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  late final _name = TextEditingController(text: widget.staff?.name ?? '');
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  late bool _active = widget.staff?.active ?? true;
  late bool _changePin = widget.staff == null;
  bool _showPin = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _pin, _pin2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_changePin) {
      if (!RegExp(r'^\d{6}$').hasMatch(_pin.text)) return setState(() => _error = 'PIN harus 6 angka.');
      if (_pin.text != _pin2.text) return setState(() => _error = 'Ulangi PIN tidak sama.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = widget.staff;
    final session = ref.read(sessionProvider.notifier);
    try {
      if (s == null) {
        await session.authed((api, token) => api.post('/staff', token: token, data: {'name': _name.text, 'pin': _pin.text}));
      } else {
        await session.authed((api, token) => api.put('/staff/${s.id}', token: token, data: {'name': _name.text, 'active': _active}));
        if (_changePin) await session.authed((api, token) => api.post('/staff/${s.id}/pin', token: token, data: {'pin': _pin.text}));
      }
      if (mounted) {
        Navigator.pop(
          context,
          s == null
              ? 'Kasir ${_name.text.trim()} ditambahkan. Masuk dengan nama & PIN-nya di layar login.'
              : _changePin
              ? 'PIN ${_name.text.trim()} diganti.'
              : 'Data ${_name.text.trim()} disimpan.',
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _firstError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final pinField = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)];
    final s = widget.staff;
    return AlertDialog(
      scrollable: true,
      title: Text(s == null ? 'Tambah kasir' : 'Ubah kasir'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama (tampil di layar login & struk)', hintText: 'mis. Sari', counterText: ''),
            ),
            if (s != null) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Aktif'),
                subtitle: Text(_active ? 'Bisa login di tablet' : 'Tidak bisa login; keluar dari semua tablet'),
              ),
              if (s.locked)
                Text('Terkunci karena PIN salah berkali-kali. Ganti PIN untuk membuka kunci.', style: AppType.caption.copyWith(color: AppColors.danger)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _changePin,
                onChanged: (v) => setState(() => _changePin = v ?? false),
                title: const Text('Ganti PIN'),
                subtitle: const Text('Kasir lupa PIN atau PIN diketahui orang lain'),
              ),
            ],
            if (_changePin) ...[
              const SizedBox(height: AppSpace.s2),
              TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                inputFormatters: pinField,
                obscureText: !_showPin,
                decoration: InputDecoration(
                  labelText: s == null ? 'PIN 6 angka' : 'PIN baru (6 angka)',
                  suffixIcon: IconButton(
                    tooltip: _showPin ? 'Sembunyikan' : 'Tampilkan',
                    onPressed: () => setState(() => _showPin = !_showPin),
                    icon: Icon(_showPin ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s3),
              TextField(
                controller: _pin2,
                keyboardType: TextInputType.number,
                inputFormatters: pinField,
                obscureText: !_showPin,
                decoration: const InputDecoration(labelText: 'Ulangi PIN'),
              ),
              const SizedBox(height: AppSpace.s1),
              Text('Hindari angka sama semua atau berurutan (mis. 111111, 123456).', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
            ],
            if (_error != null) ...[const SizedBox(height: AppSpace.s2), Text(_error!, style: AppType.caption.copyWith(color: AppColors.danger))],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Simpan')),
      ],
    );
  }
}
