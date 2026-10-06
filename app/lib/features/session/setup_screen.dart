import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import 'session_controller.dart';

/// Pendaftaran tablet oleh owner (sekali saja per tablet).
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _deviceName = TextEditingController(text: 'Tablet Kasir');
  final _otp = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Server meminta kode 2FA (owner mengaktifkan 2FA) → tampilkan kolom kode.
  bool _needsOtp = false;

  @override
  void dispose() {
    for (final c in [_server, _email, _password, _deviceName, _otp]) {
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
            serverUrl: _server.text.trim(),
            email: _email.text,
            password: _password.text,
            deviceName: _deviceName.text,
            otp: _needsOtp ? _otp.text : null,
          );
    } on ApiException catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.s6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BrandLockup(height: 48)),
                const SizedBox(height: AppSpace.s6),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s6),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Daftarkan tablet', style: AppType.headline),
                          const SizedBox(height: AppSpace.s1),
                          Text('Dilakukan sekali oleh owner. Setelah itu kasir cukup login dengan PIN.',
                              style: AppType.body.copyWith(color: AppColors.inkMuted)),
                          const SizedBox(height: AppSpace.s6),
                          TextFormField(
                            controller: _server,
                            decoration: const InputDecoration(
                              labelText: 'Alamat server',
                              hintText: 'https://pos.contoh.my.id',
                              prefixIcon: Icon(Icons.dns_rounded),
                            ),
                            keyboardType: TextInputType.url,
                            validator: (v) {
                              final uri = Uri.tryParse(v?.trim() ?? '');
                              return uri != null && uri.hasScheme && uri.host.isNotEmpty
                                  ? null
                                  : 'Isi alamat lengkap, mis. https://pos.contoh.my.id';
                            },
                          ),
                          const SizedBox(height: AppSpace.s3),
                          TextFormField(
                            controller: _email,
                            decoration: const InputDecoration(
                                labelText: 'Email owner', prefixIcon: Icon(Icons.alternate_email_rounded)),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => (v?.contains('@') ?? false) ? null : 'Email tidak valid',
                          ),
                          const SizedBox(height: AppSpace.s3),
                          TextFormField(
                            controller: _password,
                            decoration: const InputDecoration(
                                labelText: 'Password owner', prefixIcon: Icon(Icons.lock_outline_rounded)),
                            obscureText: true,
                            validator: (v) => (v?.isNotEmpty ?? false) ? null : 'Wajib diisi',
                          ),
                          const SizedBox(height: AppSpace.s3),
                          TextFormField(
                            controller: _deviceName,
                            decoration: const InputDecoration(
                                labelText: 'Nama tablet', prefixIcon: Icon(Icons.tablet_android_rounded)),
                            validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
                          ),
                          if (_needsOtp) ...[
                            const SizedBox(height: AppSpace.s3),
                            TextFormField(
                              controller: _otp,
                              autofocus: true,
                              decoration: const InputDecoration(
                                labelText: 'Kode 2FA (6 digit)',
                                helperText: 'Dari aplikasi authenticator di HP owner',
                                prefixIcon: Icon(Icons.verified_user_rounded),
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              validator: (v) =>
                                  RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '') ? null : 'Isi 6 digit kode',
                            ),
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
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5))
                                : const Text('Daftarkan'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
