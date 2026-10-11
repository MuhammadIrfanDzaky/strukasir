import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import 'account_dialogs.dart';
import 'session_controller.dart';
import 'signup_form.dart';

enum _Mode { welcome, signup, signin }

/// Tablet belum terdaftar: pilih "Daftar usaha baru" (owner baru) atau "Masuk" (tablet tambahan
/// untuk usaha yang sudah ada). Ditampilkan dalam satu layar (bukan route) supaya begitu terdaftar,
/// aplikasi langsung berpindah ke layar PIN / Kasir tanpa sisa halaman di belakang.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  _Mode _mode = _Mode.welcome;

  void _go(_Mode mode) => setState(() => _mode = mode);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _mode == _Mode.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_Mode.welcome);
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.s5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandLockup(height: 48)),
                    const SizedBox(height: AppSpace.s6),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.s6),
                        child: switch (_mode) {
                          _Mode.welcome => _Welcome(onSignup: () => _go(_Mode.signup), onSignin: () => _go(_Mode.signin)),
                          _Mode.signup => SignupForm(onBack: () => _go(_Mode.welcome)),
                          _Mode.signin => _OwnerSignIn(onBack: () => _go(_Mode.welcome)),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onSignup, required this.onSignin});

  final VoidCallback onSignup;
  final VoidCallback onSignin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Selamat datang', style: AppType.headline),
        const SizedBox(height: AppSpace.s1),
        Text('Kasir, struk, dan laporan untuk usaha Anda.', style: AppType.body.copyWith(color: AppColors.inkMuted)),
        const SizedBox(height: AppSpace.s6),
        FilledButton(onPressed: onSignup, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)), child: const Text('Daftar usaha baru'), ),
        const SizedBox(height: AppSpace.s3),
        OutlinedButton(onPressed: onSignin, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)), child: const Text('Sudah punya akun? Masuk'), ),
        const SizedBox(height: AppSpace.s3),
        Text(
          'Pakai "Masuk" untuk menambah tablet ke usaha yang sudah terdaftar.',
          textAlign: TextAlign.center,
          style: AppType.caption.copyWith(color: AppColors.inkMuted),
        ),
      ],
    );
  }
}

/// Kolom alamat server — hanya di build development (tanpa `--dart-define=API_URL`).
class ServerUrlField extends StatelessWidget {
  const ServerUrlField({super.key, required this.controller});

  final TextEditingController controller;

  static bool get needed => kApiUrl.isEmpty;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: const InputDecoration(labelText: 'Alamat server (development)', hintText: 'http://10.0.2.2:8000', ),
      keyboardType: TextInputType.url,
      validator: (v) {
        final uri = Uri.tryParse(v?.trim() ?? '');
        return uri != null && uri.hasScheme && uri.host.isNotEmpty ? null : 'Isi alamat lengkap, mis. http://10.0.2.2:8000';
      },
    );
  }
}

/// Owner yang sudah punya akun mendaftarkan tablet tambahan (email + password, + kode 2FA bila aktif).
class _OwnerSignIn extends ConsumerStatefulWidget {
  const _OwnerSignIn({required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<_OwnerSignIn> createState() => _OwnerSignInState();
}

class _OwnerSignInState extends ConsumerState<_OwnerSignIn> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  /// Server meminta kode 2FA (owner mengaktifkan 2FA) → tampilkan kolom kode.
  bool _needsOtp = false;

  /// Usaha dengan beberapa outlet: outlet yang dipilih untuk tablet ini.
  String? _outletId;

  @override
  void dispose() {
    for (final c in [_server, _email, _password, _otp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).registerDevice(
            serverUrl: ServerUrlField.needed ? _server.text.trim() : kApiUrl,
            email: _email.text,
            password: _password.text,
            otp: _needsOtp ? _otp.text : null,
            outletId: _outletId,
          );
    } on ApiException catch (e) {
      // Beberapa outlet: server meminta pilihan outlet (password sudah benar) → pilih lalu kirim ulang.
      final outlets = (e.body?['outlets'] as List?)?.cast<Map<String, dynamic>>();
      if (e.field('outlet_id') != null && outlets != null && outlets.isNotEmpty && mounted) {
        final picked = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Tablet ini untuk outlet mana?'),
            children: [
              for (final o in outlets)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, o['id'] as String),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(o['name'] as String),
                    subtitle: o['address'] == null ? null : Text(o['address'] as String),
                  ),
                ),
            ],
          ),
        );
        if (picked != null && mounted) {
          _outletId = picked;
          setState(() => _busy = false);
          return _submit();
        }
        if (mounted) setState(() => _error = 'Pilih outlet untuk tablet ini.');
        return;
      }
      final otpError = e.field('otp');
      setState(() {
        if (otpError != null) {
          _needsOtp = true;
          _otp.clear();
        }
        _error = otpError ?? e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final serverUrl = ServerUrlField.needed ? _server.text.trim() : kApiUrl;
    if (Uri.tryParse(serverUrl)?.host.isEmpty ?? true) {
      setState(() => _error = 'Isi alamat server dulu.');
      return;
    }
    final email = await showDialog<String>(
      context: context,
      builder: (_) => ForgotPasswordDialog(serverUrl: serverUrl, email: _email.text.trim()),
    );
    if (email != null && mounted) {
      setState(() {
        _email.text = email;
        _password.clear();
        _error = null;
        _info = 'Password diganti. Silakan masuk dengan password baru.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormHeader(
            title: 'Masuk sebagai owner',
            subtitle: 'Tablet ini akan ditambahkan ke usaha Anda. Setelah itu kasir cukup login dengan PIN.',
            onBack: widget.onBack,
          ),
          const SizedBox(height: AppSpace.s5),
          if (ServerUrlField.needed) ...[ServerUrlField(controller: _server), const SizedBox(height: AppSpace.s3)],
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email owner', ),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: (v) => (v?.contains('@') ?? false) ? null : 'Email tidak valid',
          ),
          const SizedBox(height: AppSpace.s3),
          TextFormField(
            controller: _password,
            decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(
                tooltip: _showPassword ? 'Sembunyikan' : 'Tampilkan',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              ), ),
            obscureText: !_showPassword,
            validator: (v) => (v?.isNotEmpty ?? false) ? null : 'Wajib diisi',
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _busy ? null : _forgot, child: const Text('Lupa password?')),
          ),
          if (_needsOtp) ...[
            const SizedBox(height: AppSpace.s3),
            TextFormField(
              controller: _otp,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Kode 2FA (6 digit)', helperText: 'Dari aplikasi authenticator di HP owner', ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '') ? null : 'Isi 6 digit kode',
            ),
          ],
          if (_info != null && _error == null) ...[
            const SizedBox(height: AppSpace.s3),
            Text(_info!, style: AppType.body.copyWith(color: AppColors.success)),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpace.s3),
            Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: AppSpace.s6),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
            child: _busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Masuk'),
          ),
        ],
      ),
    );
  }
}

/// Judul form dengan tombol kembali ke layar selamat datang.
class FormHeader extends StatelessWidget {
  const FormHeader({super.key, required this.title, required this.subtitle, required this.onBack, this.step});

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  /// Mis. "Langkah 1 dari 2".
  final String? step;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Kembali',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(padding: EdgeInsets.zero),
        ),
        const SizedBox(width: AppSpace.s2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (step != null) AppOverline(step!),
              Text(title, style: AppType.headline),
              const SizedBox(height: AppSpace.s1),
              Text(subtitle, style: AppType.body.copyWith(color: AppColors.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}
