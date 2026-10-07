import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import 'session_controller.dart';

InputDecoration _codeDecoration(String? error) => InputDecoration(
      labelText: 'Kode 6 digit dari email',
      prefixIcon: const Icon(Icons.mark_email_read_rounded),
      counterText: '',
      errorText: error,
    );

Widget _codeField(TextEditingController c, String? error, {bool autofocus = false}) => TextField(
      controller: c,
      autofocus: autofocus,
      decoration: _codeDecoration(error),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 6,
    );

/// Lupa password owner: (1) email → kode dikirim, (2) kode + password baru.
/// Dibuka dari layar "Masuk sebagai owner"; [serverUrl] dari form tersebut.
class ForgotPasswordDialog extends ConsumerStatefulWidget {
  const ForgotPasswordDialog({super.key, required this.serverUrl, this.email = ''});

  final String serverUrl;
  final String email;

  @override
  ConsumerState<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<ForgotPasswordDialog> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _info;
  String? _error;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [_email, _code, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    try {
      await action();
    } on ApiException catch (e) {
      setState(() {
        _fieldErrors = {for (final f in e.fieldErrors.keys) f: e.field(f)!};
        _error = _fieldErrors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        if (!_email.text.contains('@')) {
          setState(() => _fieldErrors = {'email': 'Email tidak valid'});
          return;
        }
        final message =
            await ref.read(sessionProvider.notifier).forgotPassword(serverUrl: widget.serverUrl, email: _email.text);
        setState(() {
          _codeSent = true;
          _info = message;
        });
      });

  Future<void> _reset() => _run(() async {
        final p = _password.text;
        if (_code.text.length != 6) {
          setState(() => _fieldErrors = {'code': 'Isi 6 angka dari email'});
          return;
        }
        if (p.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
          setState(() => _fieldErrors = {'password': 'Minimal 8 karakter, ada huruf dan angka'});
          return;
        }
        await ref.read(sessionProvider.notifier).resetPassword(
            serverUrl: widget.serverUrl, email: _email.text, code: _code.text, password: p);
        if (mounted) Navigator.pop(context, _email.text.trim());
      });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Lupa password'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _codeSent
                  ? (_info ?? 'Kode dikirim.')
                  : 'Masukkan email owner. Kami kirim kode 6 digit untuk membuat password baru.',
              style: AppType.body.copyWith(color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpace.s4),
            TextField(
              controller: _email,
              enabled: !_codeSent,
              decoration: InputDecoration(
                labelText: 'Email owner',
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                errorText: _fieldErrors['email'],
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            if (_codeSent) ...[
              const SizedBox(height: AppSpace.s3),
              _codeField(_code, _fieldErrors['code'], autofocus: true),
              const SizedBox(height: AppSpace.s3),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password baru',
                  helperText: 'Minimal 8 karakter, ada huruf dan angka',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  errorText: _fieldErrors['password'],
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _busy ? null : _sendCode, child: const Text('Kirim ulang kode')),
              ),
            ],
            if (_error != null) Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
          child: Text(_codeSent ? 'Simpan password' : 'Kirim kode'),
        ),
      ],
    );
  }
}

/// Owner yang login memverifikasi emailnya: kirim kode → masukkan kode.
class VerifyEmailDialog extends ConsumerStatefulWidget {
  const VerifyEmailDialog({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyEmailDialog> createState() => _VerifyEmailDialogState();
}

class _VerifyEmailDialogState extends ConsumerState<VerifyEmailDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _info;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      setState(() => _error = e.field('code') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
        final message = await ref.read(sessionProvider.notifier).sendEmailCode();
        setState(() {
          _sent = true;
          _info = message;
        });
      });

  Future<void> _verify() => _run(() async {
        if (_code.text.length != 6) {
          setState(() => _error = 'Isi 6 angka dari email');
          return;
        }
        await ref.read(sessionProvider.notifier).verifyEmail(_code.text);
        if (mounted) Navigator.pop(context, true);
      });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Verifikasi email'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _sent
                  ? (_info ?? 'Kode dikirim.')
                  : 'Kami kirim kode 6 digit ke ${widget.email}. Email yang terverifikasi dipakai bila Anda lupa password.',
              style: AppType.body.copyWith(color: AppColors.inkMuted),
            ),
            if (_sent) ...[
              const SizedBox(height: AppSpace.s4),
              _codeField(_code, null, autofocus: true),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _busy ? null : _send, child: const Text('Kirim ulang kode')),
              ),
            ],
            if (_error != null) Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nanti')),
        FilledButton(
          onPressed: _busy ? null : (_sent ? _verify : _send),
          child: Text(_sent ? 'Verifikasi' : 'Kirim kode'),
        ),
      ],
    );
  }
}
