import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import 'session_controller.dart';
import 'signup_form.dart' show FieldGrid, FormSection, FormSectionDivider;

void openProfile(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));

/// Profil saya: nama (& email owner), ganti PIN, ganti password (owner). Tiap bagian disimpan sendiri.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session is! LoggedIn) return const Scaffold(body: AppLoading());
    final user = session.user;
    final owner = user.role == 'owner';
    final pad = context.isCompact ? AppSpace.s4 : AppSpace.s6;
    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Profil saya')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpace.s10),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(context.isCompact ? AppSpace.s4 : AppSpace.s6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      AppAvatar(user.name, size: 56),
                      const SizedBox(width: AppSpace.s4),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(user.name, style: AppType.titleLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${owner ? 'Owner' : 'Kasir'} · ${session.device.tenantName}',
                              style: AppType.body.copyWith(color: AppColors.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ]),
                    const FormSectionDivider(),
                    _IdentitySection(key: ValueKey('${user.name}|${user.email}'), user: user),
                    const FormSectionDivider(),
                    const _PinSection(),
                    if (owner) ...[
                      const FormSectionDivider(),
                      const _PasswordSection(),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tombol simpan di kanan + pesan hasil (berhasil / gagal) di kiri.
class _SaveRow extends StatelessWidget {
  const _SaveRow({required this.busy, required this.onSave, this.error, this.done, this.label = 'Simpan'});

  final bool busy;
  final VoidCallback? onSave;
  final String? error;
  final String? done;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.s3),
        child: Row(children: [
          Expanded(
            child: error != null
                ? Text(error!, style: AppType.caption.copyWith(color: AppColors.danger))
                : done != null
                    ? Text(done!, style: AppType.caption.copyWith(color: AppColors.success))
                    : const SizedBox.shrink(),
          ),
          const SizedBox(width: AppSpace.s3),
          FilledButton(
            onPressed: busy ? null : onSave,
            child: busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
          ),
        ]),
      );
}

String _firstError(ApiException e) => e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message;

class _IdentitySection extends ConsumerStatefulWidget {
  const _IdentitySection({super.key, required this.user});

  final SessionUser user;

  @override
  ConsumerState<_IdentitySection> createState() => _IdentitySectionState();
}

class _IdentitySectionState extends ConsumerState<_IdentitySection> {
  late final _name = TextEditingController(text: widget.user.name);
  late final _email = TextEditingController(text: widget.user.email ?? '');
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _done;

  bool get _owner => widget.user.role == 'owner';
  bool get _emailChanged => _owner && _email.text.trim().toLowerCase() != (widget.user.email ?? '');

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      await ref.read(sessionProvider.notifier).updateProfile(
            name: _name.text.trim(),
            email: _owner ? _email.text.trim() : null,
            currentPassword: _emailChanged ? _password.text : null,
          );
      if (mounted) setState(() => _done = 'Tersimpan.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _firstError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => FormSection(
        title: 'Data diri',
        caption: _owner
            ? 'Nama tampil di kasir & struk. Email dipakai untuk masuk & menerima laporan; email baru perlu diverifikasi.'
            : 'Nama tampil di daftar pengguna, kasir, dan struk.',
        children: [
          FieldGrid(children: [
            TextField(
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama', counterText: ''),
            ),
            if (_owner)
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Email',
                  helperText: widget.user.emailVerified ? null : 'Belum diverifikasi',
                ),
              ),
          ]),
          if (_emailChanged) ...[
            const SizedBox(height: AppSpace.s3),
            FieldGrid(children: [
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password saat ini', helperText: 'Wajib untuk mengganti email.'),
              ),
            ]),
          ],
          _SaveRow(busy: _busy, onSave: _save, error: _error, done: _done),
        ],
      );
}

class _PinSection extends ConsumerStatefulWidget {
  const _PinSection();

  @override
  ConsumerState<_PinSection> createState() => _PinSectionState();
}

class _PinSectionState extends ConsumerState<_PinSection> {
  final _current = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _current.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pin.text != _confirm.text) {
      setState(() => _error = 'Konfirmasi PIN baru tidak sama.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      await ref.read(sessionProvider.notifier).changePin(currentPin: _current.text, pin: _pin.text);
      _current.clear();
      _pin.clear();
      _confirm.clear();
      if (mounted) setState(() => _done = 'PIN diganti. Tablet lain yang memakai akun ini perlu masuk ulang.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _firstError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  TextField _field(TextEditingController c, String label) => TextField(
        controller: c,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, counterText: ''),
      );

  @override
  Widget build(BuildContext context) => FormSection(
        title: 'Ganti PIN',
        caption: 'PIN 6 angka untuk masuk di tablet. Hindari angka sama semua atau berurutan.',
        children: [
          FieldGrid(children: [
            _field(_current, 'PIN saat ini'),
            const SizedBox.shrink(),
            _field(_pin, 'PIN baru'),
            _field(_confirm, 'Ulangi PIN baru'),
          ]),
          _SaveRow(busy: _busy, onSave: _save, error: _error, done: _done, label: 'Ganti PIN'),
        ],
      );
}

class _PasswordSection extends ConsumerStatefulWidget {
  const _PasswordSection();

  @override
  ConsumerState<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends ConsumerState<_PasswordSection> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      await ref.read(sessionProvider.notifier).changePassword(
            current: _current.text,
            password: _password.text,
            confirmation: _confirm.text,
          );
      _current.clear();
      _password.clear();
      _confirm.clear();
      if (mounted) setState(() => _done = 'Password diganti. Pemberitahuan dikirim ke email Anda.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _firstError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  TextField _field(TextEditingController c, String label) =>
      TextField(controller: c, obscureText: true, autocorrect: false, decoration: InputDecoration(labelText: label));

  @override
  Widget build(BuildContext context) => FormSection(
        title: 'Ganti password',
        caption: 'Untuk masuk & mendaftarkan tablet baru. Minimal 8 karakter berisi huruf dan angka.',
        children: [
          FieldGrid(children: [
            _field(_current, 'Password saat ini'),
            const SizedBox.shrink(),
            _field(_password, 'Password baru'),
            _field(_confirm, 'Ulangi password baru'),
          ]),
          _SaveRow(busy: _busy, onSave: _save, error: _error, done: _done, label: 'Ganti password'),
        ],
      );
}
